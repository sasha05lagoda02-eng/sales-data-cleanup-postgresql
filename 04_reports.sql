-- 04_reports.sql
-- Reporting views on top of clean.sales_lines. Read-only for the data, safe to re-run.
-- Revenue rule: all orders except status = 'cancelled'.
begin;

create schema if not exists reports;

create or replace view reports.valid_sales as
select * from clean.sales_lines where status <> 'cancelled';

-- Monthly revenue, orders, average order value, month-over-month growth
create or replace view reports.monthly_kpis as
with m as (
  select date_trunc('month', ordered_at)::date  as month,
         sum(line_total)                         as revenue,
         count(distinct order_id)                as orders,
         sum(quantity)                           as units,
         count(distinct customer_email)          as customers
  from reports.valid_sales
  group by 1
)
select month, revenue, orders, units, customers,
       round(revenue / orders, 2) as avg_order_value,
       round(100.0 * (revenue - lag(revenue) over (order by month))
             / lag(revenue) over (order by month), 1) as mom_growth_pct
from m;

-- Revenue by category with share of total
create or replace view reports.category_sales as
select category,
       sum(line_total)          as revenue,
       sum(quantity)            as units,
       count(distinct order_id) as orders,
       round(100.0 * sum(line_total) / sum(sum(line_total)) over (), 2) as revenue_share_pct
from reports.valid_sales
group by category;

-- Every product ranked inside its category
create or replace view reports.product_ranking as
select category, sku, product_name,
       sum(quantity)   as units,
       sum(line_total) as revenue,
       dense_rank() over (partition by category order by sum(line_total) desc) as rank_in_category,
       round(100.0 * sum(line_total)
             / sum(sum(line_total)) over (partition by category), 2) as share_of_category_pct
from reports.valid_sales
group by category, sku, product_name;

-- Revenue by country
create or replace view reports.country_sales as
select country,
       count(distinct customer_email) as customers,
       count(distinct order_id)       as orders,
       sum(line_total)                as revenue,
       round(sum(line_total) / count(distinct order_id), 2) as avg_order_value,
       round(100.0 * sum(line_total) / sum(sum(line_total)) over (), 2) as revenue_share_pct
from reports.valid_sales
group by country;

-- One row per customer
create or replace view reports.customer_summary as
select customer_email,
       max(customer_name)        as customer_name,
       max(country)              as country,
       count(distinct order_id)  as orders,
       sum(line_total)           as revenue,
       min(ordered_at)::date     as first_order,
       max(ordered_at)::date     as last_order,
       case when count(distinct order_id) = 1 then '1 one-time'
            when count(distinct order_id) between 2 and 5 then '2 repeat (2-5 orders)'
            else '3 loyal (6+ orders)' end as segment
from reports.valid_sales
group by customer_email;

-- Customer segments by number of orders
create or replace view reports.customer_segments as
select segment,
       count(*)      as customers,
       sum(orders)   as orders,
       sum(revenue)  as revenue,
       round(100.0 * count(*) / sum(count(*)) over (), 2)         as customers_share_pct,
       round(100.0 * sum(revenue) / sum(sum(revenue)) over (), 2) as revenue_share_pct
from reports.customer_summary
group by segment;

-- Headline numbers and cross-report reconciliation
select metric, value
from (
  select 1 as ord, 'revenue (excl. cancelled)' as metric,
         (select sum(line_total) from reports.valid_sales) as value
  union all select 2, 'orders',    (select count(distinct order_id) from reports.valid_sales)
  union all select 3, 'customers', (select count(*) from reports.customer_summary)
  union all select 4, 'average order value',
         (select round(sum(line_total) / count(distinct order_id), 2) from reports.valid_sales)
  union all select 5, 'repeat customers, % of customers',
         (select round(100.0 * count(*) filter (where orders > 1) / count(*), 2)
            from reports.customer_summary)
  union all select 6, 'cancelled orders, % of all orders',
         (select round(100.0 * count(distinct order_id) filter (where status = 'cancelled')
                       / count(distinct order_id), 2) from clean.sales_lines)
  union all select 7, 'months covered', (select count(*) from reports.monthly_kpis)
  union all select 8, 'check: monthly total - revenue (must be 0)',
         (select sum(revenue) from reports.monthly_kpis)
       - (select sum(line_total) from reports.valid_sales)
  union all select 9, 'check: category total - revenue (must be 0)',
         (select sum(revenue) from reports.category_sales)
       - (select sum(line_total) from reports.valid_sales)
  union all select 10, 'check: country total - revenue (must be 0)',
         (select sum(revenue) from reports.country_sales)
       - (select sum(line_total) from reports.valid_sales)
  union all select 11, 'check: segment total - revenue (must be 0)',
         (select sum(revenue) from reports.customer_segments)
       - (select sum(line_total) from reports.valid_sales)
) t
order by ord;

commit;
