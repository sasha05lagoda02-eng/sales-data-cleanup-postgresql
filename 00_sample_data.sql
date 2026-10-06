-- 00_sample_data.sql
-- Creates the synthetic input for the project:
--   raw.product_master  - reference list of 42 products
--   raw.sales_export    - a messy flat sales export, one row per order line, every column as text
-- The export imitates what a shop owner sends after "Export to CSV": mixed date formats,
-- decimal commas, country codes, duplicated rows, missing values.
-- No real customers are in this data.
begin;

create schema if not exists raw;
drop table if exists raw.sales_export;
drop table if exists raw.product_master cascade;

create table raw.product_master (
  sku          text primary key,
  product_name text not null,
  category     text not null,
  list_price   numeric(10,2) not null
);

insert into raw.product_master (sku, product_name, category, list_price) values
  ('SKU-0001', 'Laptops model 1',     'Laptops',     6957.67),
  ('SKU-0002', 'Phones model 1',      'Phones',      2531.12),
  ('SKU-0003', 'Audio model 1',       'Audio',       1391.25),
  ('SKU-0004', 'Monitors model 1',    'Monitors',     692.96),
  ('SKU-0005', 'Accessories model 1', 'Accessories',   48.28),
  ('SKU-0006', 'Smart Home model 1',  'Smart Home',   252.48),
  ('SKU-0007', 'Laptops model 2',     'Laptops',     5445.25),
  ('SKU-0008', 'Phones model 2',      'Phones',      2651.61),
  ('SKU-0009', 'Audio model 2',       'Audio',        885.70),
  ('SKU-0010', 'Monitors model 2',    'Monitors',    2761.87),
  ('SKU-0011', 'Accessories model 2', 'Accessories',  190.86),
  ('SKU-0012', 'Smart Home model 2',  'Smart Home',   932.51),
  ('SKU-0013', 'Laptops model 3',     'Laptops',     7530.23),
  ('SKU-0014', 'Phones model 3',      'Phones',      4623.66),
  ('SKU-0015', 'Audio model 3',       'Audio',        263.15),
  ('SKU-0016', 'Monitors model 3',    'Monitors',    1082.26),
  ('SKU-0017', 'Accessories model 3', 'Accessories',  113.57),
  ('SKU-0018', 'Smart Home model 3',  'Smart Home',   848.32),
  ('SKU-0019', 'Laptops model 4',     'Laptops',     2992.32),
  ('SKU-0020', 'Phones model 4',      'Phones',      4548.21),
  ('SKU-0021', 'Audio model 4',       'Audio',        653.53),
  ('SKU-0022', 'Monitors model 4',    'Monitors',    1451.37),
  ('SKU-0023', 'Accessories model 4', 'Accessories',  146.93),
  ('SKU-0024', 'Smart Home model 4',  'Smart Home',   478.81),
  ('SKU-0025', 'Laptops model 5',     'Laptops',     8361.58),
  ('SKU-0026', 'Phones model 5',      'Phones',      4867.93),
  ('SKU-0027', 'Audio model 5',       'Audio',       1400.60),
  ('SKU-0028', 'Monitors model 5',    'Monitors',    1565.32),
  ('SKU-0029', 'Accessories model 5', 'Accessories',  166.77),
  ('SKU-0030', 'Smart Home model 5',  'Smart Home',   634.49),
  ('SKU-0031', 'Laptops model 6',     'Laptops',     3736.46),
  ('SKU-0032', 'Phones model 6',      'Phones',      3767.84),
  ('SKU-0033', 'Audio model 6',       'Audio',        460.54),
  ('SKU-0034', 'Monitors model 6',    'Monitors',    1680.90),
  ('SKU-0035', 'Accessories model 6', 'Accessories',  102.22),
  ('SKU-0036', 'Smart Home model 6',  'Smart Home',   169.33),
  ('SKU-0037', 'Laptops model 7',     'Laptops',     7625.33),
  ('SKU-0038', 'Phones model 7',      'Phones',      5128.57),
  ('SKU-0039', 'Audio model 7',       'Audio',       1176.25),
  ('SKU-0040', 'Monitors model 7',    'Monitors',    1043.23),
  ('SKU-0041', 'Accessories model 7', 'Accessories',  267.82),
  ('SKU-0042', 'Smart Home model 7',  'Smart Home',    76.91);

create table raw.sales_export (
  src_row        bigint generated always as identity primary key,  -- line number in the source file
  order_id       text,
  order_date     text,
  status         text,
  customer_email text,
  customer_name  text,
  country        text,
  city           text,
  sku            text,
  product_name   text,
  category       text,
  quantity       text,
  unit_price     text
);

-- ---------------------------------------------------------------- clean base data
select setseed(0.42);

create temp table _cust on commit drop as
select n as customer_id,
       fn || ' ' || ln as customer_name,
       lower(fn) || '.' || replace(lower(ln), ' ', '') || n || '@example.com' as email,
       loc.country, loc.city
from (
  select n,
         (array['Anna','Jan','Piotr','Marta','Tomasz','Olena','Andrii','Iryna','Lukas','Emma',
                'Max','Sophie','Petr','Jana','Daan','Sanne','Carlos','Lucia','Maria','Pavel'])[1 + (n % 20)] as fn,
         (array['Nowak','Kowalski','Wisniewski','Shevchenko','Kovalenko','Bondarenko','Muller','Schmidt',
                'Schneider','Novak','Svoboda','Dvorak','de Vries','Jansen','Bakker','Garcia','Martinez',
                'Lopez','Fischer','Weber','Lewandowski','Melnyk','Horvat','Visser','Sanchez'])[1 + ((n / 20) % 25)] as ln
  from generate_series(1, 5000) n
) t
join (
  select row_number() over () - 1 as idx, country, city
  from (values
    ('Poland','Warsaw'),('Poland','Krakow'),('Poland','Gdansk'),('Poland','Wroclaw'),
    ('Germany','Berlin'),('Germany','Munich'),('Germany','Hamburg'),
    ('Ukraine','Kyiv'),('Ukraine','Lviv'),
    ('Czechia','Prague'),('Czechia','Brno'),
    ('Netherlands','Amsterdam'),('Netherlands','Rotterdam'),
    ('Spain','Madrid'),('Spain','Barcelona')) v(country, city)
) loc on loc.idx = (t.n * 7) % 15;

create temp table _orders on commit drop as
select o as order_no,
       timestamp '2024-01-01' + random() * (timestamp '2026-09-30' - timestamp '2024-01-01') as ordered_at,
       1 + floor(5000 * power(random(), 2))::int as customer_id,
       (array['delivered','delivered','delivered','delivered','delivered','delivered','delivered',
              'delivered','delivered','delivered','delivered',
              'shipped','shipped','paid','paid','new','new',
              'cancelled','cancelled','cancelled'])[1 + floor(random() * 20)::int] as status,
       1 + floor(random() * random() * 6)::int as n_lines
from generate_series(1, 50000) o;

create temp table _lines on commit drop as
with l as (
  select o.order_no, o.ordered_at, o.customer_id, o.status,
         1 + floor(random() * 42)::int as pidx,
         1 + floor(random() * random() * 4)::int as quantity,
         (array[1, 1, 1, 1, 0.95, 0.9])[1 + floor(random() * 6)::int] as disc
  from _orders o
  cross join lateral generate_series(1, o.n_lines) g(i)
),
d as (
  select distinct on (order_no, pidx) * from l order by order_no, pidx
)
select row_number() over (order by d.order_no, d.pidx) as line_no,
       d.order_no, d.ordered_at, d.customer_id, d.status,
       pm.sku, pm.product_name, pm.category,
       d.quantity,
       round(pm.list_price * d.disc, 2) as unit_price
from d
join (select row_number() over (order by sku) as idx, * from raw.product_master) pm on pm.idx = d.pidx;

-- ---------------------------------------------------------------- export with injected problems
insert into raw.sales_export
  (order_id, order_date, status, customer_email, customer_name, country, city,
   sku, product_name, category, quantity, unit_price)
select
  'ORD-' || lpad(x.order_no::text, 6, '0'),
  -- two date formats; a few orders dated three years ahead
  case when x.order_no % 19 = 0
       then to_char(x.ordered_at + case when x.order_no % 4999 = 0 then interval '3 years' else interval '0' end,
                    'DD.MM.YYYY HH24:MI')
       else to_char(x.ordered_at + case when x.order_no % 4999 = 0 then interval '3 years' else interval '0' end,
                    'YYYY-MM-DD HH24:MI:SS') end,
  -- status spelling variants
  case when x.status = 'cancelled' and x.order_no % 5 = 0 then 'canceled'
       when x.order_no % 17 = 0 then initcap(x.status)
       when x.order_no % 43 = 0 then upper(x.status) || ' '
       else x.status end,
  -- missing, upper-case and padded emails
  case when x.line_no % 211 = 0 then ''
       when x.line_no % 37 = 0 then upper(c.email)
       when x.line_no % 41 = 0 then c.email || ' '
       else c.email end,
  c.customer_name,
  -- country codes and case variants
  case when x.order_no % 23 = 0 then case c.country when 'Poland' then 'PL' when 'Germany' then 'DE'
                                          when 'Ukraine' then 'UA' when 'Czechia' then 'CZ'
                                          when 'Netherlands' then 'NL' when 'Spain' then 'ES' end
       when x.order_no % 29 = 0 then lower(c.country)
       when x.order_no % 31 = 0 then upper(c.country) || ' '
       else c.country end,
  case when c.customer_id % 20 = 0 then null
       when c.customer_id % 53 = 0 then ''
       else c.city end,
  -- SKUs that are not in the product master
  case when x.line_no % 487 = 0 then 'SKU-9' || lpad((x.line_no % 900)::text, 3, '0') else x.sku end,
  case when x.line_no % 45 = 0 then lower(x.product_name)
       when x.line_no % 61 = 0 then x.product_name || ' (old)'
       else x.product_name end,
  case when x.line_no % 73 = 0 then '' else x.category end,
  -- zero, negative and empty quantities
  case when x.line_no % 331 = 0 then '0'
       when x.line_no % 997 = 0 then '-1'
       when x.line_no % 1499 = 0 then ''
       else x.quantity::text end,
  -- decimal commas and currency symbols
  case when x.line_no % 33 = 0 then replace(x.unit_price::text, '.', ',')
       when x.line_no % 97 = 0 then '$' || x.unit_price::text
       else x.unit_price::text end
from (
  select l.*, 1 as copy from _lines l
  union all
  select l.*, 2 as copy from _lines l where l.line_no % 83 = 0   -- rows exported twice
) x
join _cust c on c.customer_id = x.customer_id
order by md5(x.line_no::text || '-' || x.copy::text);

select (select count(*) from raw.product_master) as products,
       (select count(*) from raw.sales_export)   as export_rows,
       (select count(distinct order_id) from raw.sales_export) as orders;

commit;
