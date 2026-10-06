-- 03_verification.sql
-- Read-only checks on the cleanup result. Every check must return 0 violations.
with checks as (
  select 1 as check_no, 'row count: raw = clean + rejected' as check_name,
         abs((select count(*) from raw.sales_export)
           - (select count(*) from clean.sales_lines)
           - (select count(*) from clean.rejects))::numeric as violations
  union all
  select 2, 'no row is both clean and rejected',
         (select count(*) from clean.sales_lines c join clean.rejects r on r.src_row = c.src_row)
  union all
  select 3, 'no duplicate lines in clean data',
         (select count(*) from (
            select 1 from clean.sales_lines
            group by order_id, ordered_at, status, customer_email, sku, quantity, unit_price
            having count(*) > 1) d)
  union all
  select 4, 'emails are trimmed and lowercase',
         (select count(*) from clean.sales_lines where customer_email <> lower(btrim(customer_email)))
  union all
  select 5, 'country is in the standard list',
         (select count(*) from clean.sales_lines
           where country not in ('Poland','Germany','Ukraine','Czechia','Netherlands','Spain'))
  union all
  select 6, 'no order dates in the future',
         (select count(*) from clean.sales_lines where ordered_at > current_timestamp)
  union all
  select 7, 'product name and category match the product master',
         (select count(*) from clean.sales_lines c join raw.product_master m on m.sku = c.sku
           where c.product_name <> m.product_name or c.category <> m.category)
  union all
  select 8, 'one email, status and date per order',
         (select count(*) from (
            select 1 from clean.sales_lines
            group by order_id
            having count(distinct customer_email) > 1
                or count(distinct status) > 1
                or count(distinct ordered_at) > 1) o)
  union all
  select 9, 'every change log entry points to a clean row',
         (select count(*) from clean.change_log l
           where not exists (select 1 from clean.sales_lines c where c.src_row = l.src_row))
  union all
  select 10, 'control total: clean revenue = revenue recomputed from raw text',
         (select abs(sum(c.line_total)
                   - sum(replace(replace(btrim(s.unit_price), '$', ''), ',', '.')::numeric * s.quantity::int))
            from clean.sales_lines c join raw.sales_export s on s.src_row = c.src_row)
  union all
  select 11, 'control total: sum by month = sum by category = grand total',
         (select abs((select sum(x) from (select sum(line_total) x from clean.sales_lines
                                          group by date_trunc('month', ordered_at)) a)
                   - (select sum(line_total) from clean.sales_lines))
               + abs((select sum(x) from (select sum(line_total) x from clean.sales_lines
                                          group by category) b)
                   - (select sum(line_total) from clean.sales_lines)))
)
select check_no,
       check_name,
       violations,
       case when violations = 0 then 'PASS' else 'FAIL' end as result
from checks
order by check_no;
