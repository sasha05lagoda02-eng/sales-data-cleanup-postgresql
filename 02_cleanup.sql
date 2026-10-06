-- 02_cleanup.sql
-- Builds clean.sales_lines from raw.sales_export.
-- Every changed cell goes to clean.change_log, every dropped row to clean.rejects.
-- The raw table is never modified. Safe to re-run.
begin;

create schema if not exists clean;
drop table if exists clean.sales_lines, clean.change_log, clean.rejects;

create table clean.rejects (
  src_row bigint primary key,
  reason  text not null
);

create table clean.change_log (
  src_row     bigint not null,
  column_name text   not null,
  old_value   text,
  new_value   text,
  rule        text   not null
);

create table clean.sales_lines (
  src_row        bigint primary key,
  order_id       text          not null,
  ordered_at     timestamp     not null,
  status         text          not null check (status in ('new','paid','shipped','delivered','cancelled')),
  customer_email text          not null,
  customer_name  text,
  country        text          not null,
  city           text,
  sku            text          not null references raw.product_master (sku),
  product_name   text          not null,
  category       text          not null,
  quantity       int           not null check (quantity > 0),
  unit_price     numeric(10,2) not null check (unit_price >= 0),
  line_total     numeric(12,2) generated always as (quantity * unit_price) stored
);

-- 1. Candidate values for every raw row
create temp table stg on commit drop as
with d as (
  select s.*,
         row_number() over (
           partition by s.order_id, s.order_date, s.status, s.customer_email, s.customer_name,
                        s.country, s.city, s.sku, s.product_name, s.category, s.quantity, s.unit_price
           order by s.src_row) as copy_no
  from raw.sales_export s
),
n as (
  select d.*,
         case
           when d.order_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
             then d.order_date::timestamp
           when d.order_date ~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$'
             then to_timestamp(d.order_date, 'DD.MM.YYYY HH24:MI')::timestamp
         end as ordered_at,
         case lower(btrim(d.status)) when 'canceled' then 'cancelled'
              else lower(btrim(d.status)) end as status_n,
         nullif(lower(btrim(d.customer_email)), '') as email_n,
         case upper(btrim(d.country))
           when 'PL' then 'Poland'      when 'POLAND'      then 'Poland'
           when 'DE' then 'Germany'     when 'GERMANY'     then 'Germany'
           when 'UA' then 'Ukraine'     when 'UKRAINE'     then 'Ukraine'
           when 'CZ' then 'Czechia'     when 'CZECHIA'     then 'Czechia'
           when 'NL' then 'Netherlands' when 'NETHERLANDS' then 'Netherlands'
           when 'ES' then 'Spain'       when 'SPAIN'       then 'Spain'
         end as country_n,
         nullif(btrim(d.city), '') as city_n,
         m.product_name as master_name,
         m.category     as master_category,
         (m.sku is not null) as sku_known,
         case when d.quantity ~ '^[1-9]\d*$' then d.quantity::int end as qty_n,
         case when replace(replace(btrim(d.unit_price), '$', ''), ',', '.') ~ '^\d+(\.\d+)?$'
              then replace(replace(btrim(d.unit_price), '$', ''), ',', '.')::numeric(10,2) end as price_n
  from d
  left join raw.product_master m on m.sku = d.sku
),
e as (
  -- an order's email, taken from its other lines, only if they all agree
  select order_id, min(email_n) as order_email
  from n
  where email_n is not null
  group by order_id
  having count(distinct email_n) = 1
)
select n.*,
       coalesce(n.email_n, e.order_email) as email_final,
       (n.email_n is null and e.order_email is not null) as email_recovered
from n
left join e on e.order_id = n.order_id;

-- 2. Rows that cannot be repaired
insert into clean.rejects (src_row, reason)
select src_row, reason
from (
  select src_row,
         case
           when copy_no > 1                    then 'exact duplicate of an earlier row'
           when ordered_at is null             then 'order date not parseable'
           when ordered_at > current_timestamp then 'order date in the future'
           when not sku_known                  then 'SKU not in product master'
           when qty_n is null                  then 'quantity missing or not positive'
           when price_n is null                then 'unit price not numeric'
           when status_n not in ('new','paid','shipped','delivered','cancelled')
                                               then 'status not recognized'
           when country_n is null              then 'country not recognized'
           when email_final is null            then 'customer email missing, not recoverable from the order'
         end as reason
  from stg
) r
where reason is not null;

-- 3. Clean rows
insert into clean.sales_lines
  (src_row, order_id, ordered_at, status, customer_email, customer_name,
   country, city, sku, product_name, category, quantity, unit_price)
select s.src_row, s.order_id, s.ordered_at, s.status_n, s.email_final, btrim(s.customer_name),
       s.country_n, s.city_n, s.sku, s.master_name, s.master_category, s.qty_n, s.price_n
from stg s
where not exists (select 1 from clean.rejects r where r.src_row = s.src_row);

-- 4. Change log: one entry per changed cell
insert into clean.change_log (src_row, column_name, old_value, new_value, rule)
select s.src_row, v.column_name, v.old_value, v.new_value, v.rule
from stg s
join clean.sales_lines c on c.src_row = s.src_row
cross join lateral (values
  ('status',         s.status,         s.status_n,
     'trim, lowercase, canceled -> cancelled'),
  ('customer_email', s.customer_email, s.email_final,
     case when s.email_recovered then 'filled from another line of the same order'
          else 'trim, lowercase' end),
  ('country',        s.country,        s.country_n,
     'mapped to standard country name'),
  ('city',           s.city,           s.city_n,
     'blank converted to NULL'),
  ('order_date',     s.order_date,     to_char(s.ordered_at, 'YYYY-MM-DD HH24:MI:SS'),
     'converted to ISO timestamp'),
  ('unit_price',     s.unit_price,     s.price_n::text,
     'removed currency symbol / decimal comma'),
  ('product_name',   s.product_name,   s.master_name,
     'replaced with product master name'),
  ('category',       s.category,       s.master_category,
     'filled from product master')
) as v(column_name, old_value, new_value, rule)
where v.old_value is distinct from v.new_value;

-- 5. Summary
select metric, value
from (
  select 1 as ord, 'raw rows' as metric, (select count(*) from raw.sales_export) as value
  union all select 2, 'clean rows',    (select count(*) from clean.sales_lines)
  union all select 3, 'rejected rows', (select count(*) from clean.rejects)
  union all select 4, 'raw - clean - rejected (must be 0)',
                   (select count(*) from raw.sales_export)
                 - (select count(*) from clean.sales_lines)
                 - (select count(*) from clean.rejects)
  union all select 5, 'change log entries', (select count(*) from clean.change_log)
  union all
  select 10 + row_number() over (order by count(*) desc), 'rejected: ' || reason, count(*)
  from clean.rejects group by reason
  union all
  select 30 + row_number() over (order by count(*) desc), 'changed: ' || column_name, count(*)
  from clean.change_log group by column_name
  union all
  select 50, 'emails recovered from same order',
         (select count(*) from clean.change_log
           where rule = 'filled from another line of the same order')
) t
order by ord;

commit;
