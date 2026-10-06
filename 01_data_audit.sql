-- 01_data_audit.sql
-- Data quality audit of the raw sales export. Read-only: changes nothing.
with src as (
  select s.*,
         m.sku          as master_sku,
         m.product_name as master_name,
         case
           when s.order_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
             then s.order_date::timestamp
           when s.order_date ~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$'
             then to_timestamp(s.order_date, 'DD.MM.YYYY HH24:MI')::timestamp
         end as order_ts,
         row_number() over (
           partition by s.order_id, s.order_date, s.status, s.customer_email, s.customer_name,
                        s.country, s.city, s.sku, s.product_name, s.category, s.quantity, s.unit_price
           order by s.src_row) as copy_no
  from raw.sales_export s
  left join raw.product_master m on m.sku = s.sku
),
c as (
  select
    count(*)                                                                    as total_rows,
    count(*) filter (where copy_no > 1)                                         as duplicate_rows,
    count(*) filter (where coalesce(btrim(customer_email), '') = '')            as email_missing,
    count(*) filter (where btrim(customer_email) <> ''
                       and customer_email <> lower(btrim(customer_email)))      as email_not_normalized,
    count(*) filter (where country is null or country not in
                       ('Poland','Germany','Ukraine','Czechia','Netherlands','Spain')) as country_not_standard,
    count(*) filter (where coalesce(btrim(city), '') = '')                      as city_missing,
    count(*) filter (where status is null or status not in
                       ('new','paid','shipped','delivered','cancelled'))        as status_not_standard,
    count(*) filter (where order_ts is null)                                    as date_unparseable,
    count(*) filter (where order_date !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$') as date_not_iso,
    count(*) filter (where order_ts > current_timestamp)                        as date_in_future,
    count(*) filter (where unit_price is null or unit_price !~ '^\d+(\.\d+)?$') as price_not_numeric,
    count(*) filter (where quantity is null or quantity !~ '^[1-9]\d*$')        as quantity_invalid,
    count(*) filter (where master_sku is null)                                  as sku_unknown,
    count(*) filter (where master_sku is not null and product_name <> master_name) as product_name_mismatch,
    count(*) filter (where coalesce(btrim(category), '') = '')                  as category_missing
  from src
)
select v.check_no,
       v.check_name,
       v.rows_affected,
       round(100.0 * v.rows_affected / c.total_rows, 2) as pct_of_rows
from c
cross join lateral (values
  ( 1, 'total rows in export',                c.total_rows),
  ( 2, 'exact duplicate rows (extra copies)', c.duplicate_rows),
  ( 3, 'customer email missing',              c.email_missing),
  ( 4, 'customer email not normalized',       c.email_not_normalized),
  ( 5, 'country not in standard list',        c.country_not_standard),
  ( 6, 'city missing',                        c.city_missing),
  ( 7, 'status not in standard list',         c.status_not_standard),
  ( 8, 'order date not parseable',            c.date_unparseable),
  ( 9, 'order date not in ISO format',        c.date_not_iso),
  (10, 'order date in the future',            c.date_in_future),
  (11, 'unit price not a plain number',       c.price_not_numeric),
  (12, 'quantity missing or not positive',    c.quantity_invalid),
  (13, 'SKU not in product master',           c.sku_unknown),
  (14, 'product name differs from master',    c.product_name_mismatch),
  (15, 'category missing',                    c.category_missing)
) as v(check_no, check_name, rows_affected)
order by v.check_no;
