# Sales Data Cleanup and Reporting (PostgreSQL)

A messy sales export of 102,581 rows is audited, cleaned, verified and turned into reports,
using plain SQL on PostgreSQL. Every corrected cell is logged, every dropped row has a reason,
and the totals are reconciled back to the raw file.

The dataset is synthetic. It imitates a flat "Export to CSV" from a small online shop:
all columns arrive as text, with mixed date formats, decimal commas, country codes,
duplicated rows and missing values. No real customers are in it.

## What is in the repository

| File | Purpose |
|---|---|
| `sql/00_sample_data.sql` | Creates the product master and generates the messy export (reproducible) |
| `sql/01_data_audit.sql` | Read-only audit: counts every data quality problem in the raw export |
| `sql/02_cleanup.sql` | Builds the clean table, the change log and the list of rejected rows |
| `sql/03_verification.sql` | Read-only checks proving the cleanup is correct; all must return 0 |
| `sql/04_reports.sql` | Reporting views: monthly KPIs, categories, products, countries, customer segments |
| `sales_report.xlsx` | The reports and the cleanup summary as an Excel workbook with charts |

## Input

| Table | Rows | Description |
|---|---|---|
| `raw.sales_export` | 102,581 | One row per order line, 12 text columns, 50,000 orders |
| `raw.product_master` | 42 | Reference list: SKU, product name, category, list price |

## Step 1. Audit

`01_data_audit.sql` reports the problems found before anything is changed.

| Check | Rows | Share of rows |
|---|---:|---:|
| Exact duplicate rows (extra copies) | 1,221 | 1.19% |
| Customer email missing | 485 | 0.47% |
| Customer email not normalized (case, spaces) | 5,184 | 5.05% |
| Country not in standard list (codes, case variants) | 10,926 | 10.65% |
| City missing | 6,558 | 6.39% |
| Status not in standard list | 11,056 | 10.78% |
| Order date not parseable | 0 | 0.00% |
| Order date not in ISO format | 5,488 | 5.35% |
| Order date in the future | 24 | 0.02% |
| Unit price not a plain number (decimal comma, `$`) | 4,133 | 4.03% |
| Quantity missing or not positive | 478 | 0.47% |
| SKU not in product master | 210 | 0.20% |
| Product name differs from master | 3,917 | 3.82% |
| Category missing | 1,404 | 1.37% |

One row can have several problems, so the column is not a total.

## Step 2. Cleanup rules

`02_cleanup.sql` never modifies the raw table. It writes three tables in schema `clean`.

**Repaired and logged in `clean.change_log`** (source row, column, old value, new value, rule):

| Column | Rule | Cells changed |
|---|---|---:|
| status | trim, lowercase, `canceled` -> `cancelled` | 10,823 |
| country | mapped to standard country name | 10,712 |
| order_date | converted to ISO timestamp | 5,369 |
| customer_email | trim, lowercase | 5,091 |
| unit_price | removed currency symbol / decimal comma | 4,055 |
| product_name | replaced with product master name | 3,848 |
| city | blank converted to NULL | 1,618 |
| category | filled from product master | 1,379 |
| customer_email | filled from another line of the same order | 358 |
| **Total** | | **43,253** |

**Rejected and listed in `clean.rejects`** with a reason:

| Reason | Rows |
|---|---:|
| Exact duplicate of an earlier row | 1,221 |
| Quantity missing or not positive | 474 |
| SKU not in product master | 208 |
| Customer email missing, not recoverable from the order | 121 |
| Order date in the future | 24 |
| **Total** | **2,048** |

Two rules were business decisions rather than technical ones:

- **Missing email.** The email is restored only when the other lines of the same order all carry
  the same address (358 rows). Otherwise the row is rejected (121 rows). Nothing is guessed.
- **Future dates.** The correct date cannot be derived from the data, so these rows are rejected
  and listed for review instead of being kept or silently corrected.

**Result**

| | Rows |
|---|---:|
| Raw rows | 102,581 |
| Clean rows (`clean.sales_lines`) | 100,533 |
| Rejected rows (`clean.rejects`) | 2,048 |
| Raw - clean - rejected | 0 |

## Step 3. Verification

`03_verification.sql` runs 11 independent checks on the result. Each one looks for a violation
and must find none.

| # | Check | Violations |
|---|---|---:|
| 1 | Row count: raw = clean + rejected | 0 |
| 2 | No row is both clean and rejected | 0 |
| 3 | No duplicate lines in clean data | 0 |
| 4 | Emails are trimmed and lowercase | 0 |
| 5 | Country is in the standard list | 0 |
| 6 | No order dates in the future | 0 |
| 7 | Product name and category match the product master | 0 |
| 8 | One email, status and date per order | 0 |
| 9 | Every change log entry points to a clean row | 0 |
| 10 | Control total: clean revenue = revenue recomputed from the raw text | 0.00 |
| 11 | Control total: sum by month = sum by category = grand total | 0.00 |

Check 10 recomputes revenue directly from the raw text columns and compares it with the clean
table, so a pricing or quantity error introduced by the cleanup would show up here.

## Step 4. Reports

`04_reports.sql` creates views in schema `reports`. Revenue rule: every order except status
`cancelled`; unpaid orders with status `new` are included.

| Metric | Value |
|---|---:|
| Revenue | 291,565,539.56 |
| Orders | 42,285 |
| Customers | 4,986 |
| Average order value | 6,895.25 |
| Cancelled orders, share of all orders | 14.92% |
| Period | Jan 2024 - Sep 2026 (33 months) |
| Largest category | Laptops, 46.87% of revenue |
| Largest country | Poland, 25.60% of revenue |

| View | Content |
|---|---|
| `reports.monthly_kpis` | Revenue, orders, units, customers, average order value, month-over-month growth |
| `reports.category_sales` | Revenue, units, orders and revenue share by category |
| `reports.product_ranking` | Every product ranked inside its category, with share of category |
| `reports.country_sales` | Customers, orders, revenue and average order value by country |
| `reports.customer_summary` | One row per customer: orders, revenue, first and last order, segment |
| `reports.customer_segments` | One-time, repeat (2-5 orders) and loyal (6+) customers |

The script ends with a reconciliation: the monthly, category, country and segment reports all add
up to the same revenue total. `sales_report.xlsx` repeats this check with Excel formulas.

## How to run

Tested on PostgreSQL 17.11. Run the files in order from any SQL client:

```
sql/00_sample_data.sql    -- creates schema raw and 102,581 rows
sql/01_data_audit.sql     -- read-only
sql/02_cleanup.sql        -- creates schema clean
sql/03_verification.sql   -- read-only, expect 11 x PASS
sql/04_reports.sql        -- creates schema reports
```

The generator uses a fixed random seed. Re-running `00_sample_data.sql` on the test server
produced an identical export (same rows, same values), so the figures above can be reproduced.

## Known limitations

- **Synthetic data.** Business figures reflect the generator, not a real shop. For example,
  97.93% of customers are repeat buyers because 50,000 orders were spread over 5,000 customers.
- **Partially rejected orders.** 515 orders lost at least one line to rejection while their other
  lines were kept, so their totals are understated. 298 orders were rejected completely.
  All affected rows are listed in `clean.rejects`.
- **Duplicates are exact copies only.** Two rows that describe the same sale with different
  spelling are not detected.
- **Country mapping is a fixed list** of six countries and their two-letter codes. A new country
  in the input is rejected, not guessed.
- **Only `$` is handled** as a currency symbol; there is no currency conversion.
- **Missing cities stay empty.** 6,429 clean rows have no city; the data offers no reliable way
  to fill them.
- **The future-date rule uses the current time,** so results depend on the day the script runs.

## Tools

PostgreSQL 17, SQL (CTEs, window functions, regular expressions, generated columns, constraints),
Excel.
