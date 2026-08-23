# Low-Level Design (LLD)
### Bank Savings Account Data Platform — dbt + Snowflake

| | |
|---|---|
| **Document Owner** | Kumara Nagula |
| **Status** | Baseline (v1.0) |
| **Prerequisite reading** | `docs/HLD.md`, `docs/ER_DIAGRAM.md` |

This document is the module-level companion to the HLD: exact table
schemas, transformation logic, materialization config, and test coverage
for every object in the pipeline. Where the HLD explains *what* and *why*,
this explains *how*.

---

## 1. Naming Conventions

| Prefix | Layer | Example |
|---|---|---|
| `RAW_*` | Raw/landing table | `RAW_TRANSACTIONS` |
| `stg_*` | Staging view | `stg_transactions` |
| `int_*` | Intermediate (ephemeral) | `int_transactions_with_balance` |
| `dim_*` | Dimension | `dim_customers` |
| `fct_*` | Fact | `fct_transactions` |
| `mart_*` | Aggregate / reporting mart | `mart_account_monthly_summary` |
| `*_snapshot` | dbt snapshot (SCD2 source) | `accounts_snapshot` |

Snake_case throughout; Snowflake object names uppercase at the RAW layer
(matches Snowflake default), lowercase dbt model names elsewhere (dbt
convention).

---

## 2. Raw Layer — Table DDL

Schema: `BANK_DB.RAW`. Column types intentionally loose (mostly `VARCHAR`)
— this layer mirrors the source file 1:1 and defers real typing to
staging, which is standard landing-zone practice (don't let a load fail on
a type-cast issue; let dbt catch it downstream with a test instead).

```sql
CREATE OR REPLACE TABLE RAW_BRANCHES (
    branch_id       VARCHAR,
    branch_name     VARCHAR,
    city            VARCHAR,
    state           VARCHAR,
    ifsc_code       VARCHAR,
    opened_date     DATE
);

CREATE OR REPLACE TABLE RAW_CUSTOMERS (
    customer_id     VARCHAR,
    first_name      VARCHAR,
    last_name       VARCHAR,
    dob             DATE,
    email           VARCHAR,
    phone           VARCHAR,
    address         VARCHAR,
    city            VARCHAR,
    state           VARCHAR,
    kyc_status      VARCHAR,
    created_at      TIMESTAMP_NTZ
);

-- Loaded twice (day1 / day2) to feed the dbt snapshot for SCD Type 2
CREATE OR REPLACE TABLE RAW_ACCOUNTS (
    account_id      VARCHAR,
    customer_id     VARCHAR,
    branch_id       VARCHAR,
    account_type    VARCHAR,
    account_status  VARCHAR,
    interest_rate   NUMBER(5,2),
    opened_date     DATE,
    closed_date     DATE,
    updated_at      TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE RAW_TRANSACTIONS (
    transaction_id  VARCHAR,
    account_id      VARCHAR,
    txn_date        TIMESTAMP_NTZ,
    txn_type        VARCHAR,
    amount          NUMBER(12,2),
    channel         VARCHAR,
    created_at      TIMESTAMP_NTZ,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()  -- load audit column
);
```

`_loaded_at` on `RAW_TRANSACTIONS` is a load-audit column (defaults to
`CURRENT_TIMESTAMP()` at COPY time) — useful for debugging "when did this
row actually land" independent of the business `txn_date`.

---

## 3. Staging Layer — Transformation Logic

**Materialization:** `view` (default, set in `dbt_project.yml`). Views,
not tables, because staging exists purely to normalize types/names — no
storage cost justified, and a view always reflects RAW without a rebuild.

**Transformation rules applied at this layer:**
- Rename to consistent snake_case business-friendly column names
- Explicit `::type` casts (e.g., `NUMBER` precision confirmed, string
  trims)
- No joins, no aggregation, no business logic — 1:1 grain preserved with
  RAW
- Source freshness thresholds defined in `_sources.yml` (`loaded_at_field`
  + `config.freshness.warn_after` / `error_after`)

This is deliberately the same discipline as an Informatica "Source
Qualifier + Expression" stage that only cleans/types data, before any
lookup or joiner transformation happens — same concept, different tool.

---

## 4. Intermediate Layer — Business Logic

**Materialization:** `ephemeral` — compiled inline into whatever
references them (marts), never persisted as their own table/view in
Snowflake. Chosen because nothing outside the marts layer needs to query
these directly; keeping them ephemeral avoids warehouse clutter and extra
compute for a materialization no one queries standalone.

### 4.1 `int_accounts_enriched`
Joins `stg_accounts` to branch/customer context needed by downstream
dimension builds. No aggregation.

### 4.2 `int_transactions_with_balance`
Core business logic: computes a **running balance per account** using a
window function over `stg_transactions`:

```sql
sum(signed_amount) over (
    partition by account_id
    order by txn_date
    rows between unbounded preceding and current row
) as running_balance
```

`signed_amount` itself is derived from `txn_type` (deposit → positive,
withdrawal → negative) upstream in staging/this model — this is the kind
of business rule that belongs in the intermediate layer, not staging
(too much logic) and not the mart (too reusable/needs isolation for
testing).

---

## 5. SCD Type 2 — `accounts_snapshot`

**Mechanism:** dbt snapshot, **timestamp strategy**, tracked column:
`updated_at`.

```yaml
strategy: timestamp
updated_at: updated_at
unique_key: account_id
```

**How it behaves on each `dbt snapshot` run:**
1. New `account_id` in source, not in snapshot table → insert as new
   current row (`dbt_valid_from = updated_at`, `dbt_valid_to = null`).
2. Existing `account_id`, `updated_at` unchanged → no action (row is
   already current).
3. Existing `account_id`, `updated_at` newer than the current row's →
   close out the current row (`dbt_valid_to = new updated_at`) **and**
   insert a new current row with the new attribute values.
4. Deleted from source (if `invalidate_hard_deletes` is on) → close out
   the row with no successor.

**Test fixture in this project:** 400 of the 3,500 accounts have a
deliberately different `interest_rate`/`account_status`/`updated_at` in
`accounts_day2.csv` vs. `accounts_day1.csv` — running `dbt snapshot`
after loading day2 produces exactly the versioning behavior in case 3
above, which is how the SCD2 mechanism gets exercised and demoed.

**Downstream consumption:** `dim_accounts_scd2` is a thin pass-through
selecting from the snapshot and renaming `dbt_valid_from`/`dbt_valid_to`
to `valid_from`/`valid_to`, plus a derived `is_current` boolean. Grain is
`(account_id, valid_from)` — see `docs/ER_DIAGRAM.md` §4 for why this
matters for joins.

---

## 6. Incremental Fact — `fct_transactions`

```sql
{{
    config(
        materialized='incremental',
        unique_key='transaction_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        cluster_by=['txn_date_key'],
        snowflake_warehouse='BANK_WH'
    )
}}
```

| Config | Value | Why |
|---|---|---|
| `materialized` | `incremental` | Avoids reprocessing all 50K+ rows every run; only new batches get transformed |
| `unique_key` | `transaction_id` | Merge target key — required for `merge` strategy to know what to upsert on |
| `incremental_strategy` | `merge` | Snowflake-native `MERGE` statement; handles both insert (new txns) and update (late-arriving corrections) in one operation |
| `on_schema_change` | `append_new_columns` | If a new column is added upstream later, don't fail the run — add it rather than erroring |
| `cluster_by` | `txn_date_key` | Most queries filter by date range; clustering keeps same-date rows physically co-located for pruning |
| `snowflake_warehouse` | `BANK_WH` | Explicit warehouse override at the model level (Snowflake-specific dbt config) — lets a heavier model run on a bigger warehouse independent of the profile default |

**Incremental filter (watermark logic):**
```sql
{% if is_incremental() %}
where txn_date > (select coalesce(max(txn_date), '1900-01-01') from {{ this }})
{% endif %}
```
On the first run (`--full-refresh` or empty target), `is_incremental()`
is false and the whole `int_transactions_with_balance` result set loads.
On every subsequent run, only rows newer than the current max `txn_date`
already in the table are processed — this is what let batch 2 (10,000
rows) load without touching the 40,000 rows from batch 1.

**Known simplification:** this watermark assumes `txn_date` is monotonic
and append-only per load. A production version handling
out-of-order/late-arriving transactions would need a more defensive
watermark (e.g., a `_loaded_at` cutoff instead of `txn_date`, or a full
`merge` with no filter and a change-detection hash).

---

## 7. Mart Layer — Object Detail

| Model | Materialization | Grain | Key transformation |
|---|---|---|---|
| `dim_branches` | table (default) | 1 row / branch | Pass-through rename from `stg_branches` |
| `dim_customers` | table | 1 row / customer | Derives `full_name` (concat), `age` from `dob` |
| `dim_accounts_scd2` | table | 1 row / account / version | Sourced from `accounts_snapshot`; adds `is_current` |
| `fct_transactions` | incremental | 1 row / transaction | See §6 |
| `mart_account_monthly_summary` | table | 1 row / account / month | `group by account_id, date_trunc('month', txn_date)`; sums deposits/withdrawals, takes `max(running_balance)` as month-end balance |

---

## 8. Macros

### 8.1 `calculate_annual_interest(balance_column, rate_column)`
```sql
{% macro calculate_annual_interest(balance_column, rate_column) %}
    round(({{ balance_column }} * {{ rate_column }} / 100), 2)
{% endmacro %}
```
Reusable interest calculation — avoids the same arithmetic being
copy-pasted anywhere balance × rate is needed. Not currently called in a
model (available for a future "projected annual interest" mart);
included to demonstrate macro authoring for reusable business logic.

### 8.2 `set_query_tag()`
```sql
{% macro set_query_tag() -%}
  {% set new_query_tag = "dbt|" ~ model.name ~ "|" ~ invocation_id %}
  ...
  alter session set query_tag = '{{ new_query_tag }}';
{%- endmacro %}
```
Sets Snowflake's session `QUERY_TAG` to `dbt|<model_name>|<invocation_id>`
before each model runs. This means every query dbt issues is traceable in
`QUERY_HISTORY` back to the specific model and dbt run that issued it —
a real cost-attribution and debugging pattern used in production
Snowflake+dbt shops, not just decorative.

---

## 9. Test Inventory (38 total)

| Test type | Applied to | Example |
|---|---|---|
| `not_null` | Primary/foreign keys across all staging + mart models | `stg_transactions.transaction_id` |
| `unique` | Primary keys | `dim_customers.customer_id` |
| `relationships` | FK integrity between marts | `fct_transactions.account_id` → `dim_accounts_scd2.account_id` |
| `accepted_values` | Enumerated columns | `stg_accounts.account_status` in `('ACTIVE','DORMANT','CLOSED')` |
| `dbt_expectations.expect_column_values_to_be_between` | Numeric ranges | `interest_rate` between 0 and 15 |
| `dbt_utils.unique_combination_of_columns` | Composite-grain tables | `(account_id, valid_from)` on `dim_accounts_scd2`; `(account_id, txn_month)` on the monthly mart |
| Singular test (custom SQL) | Business rule | `assert_no_extreme_negative_balance.sql` — fails the build if any `running_balance` drops below a defined threshold, catching a broken running-balance calculation before it reaches the mart |

All generic test `arguments` are nested per current dbt YAML syntax
(`arguments: {...}` block under each test), matching what the validated
`dbt parse` run in this project confirmed.

---

## 10. Error Handling & Data Quality Gates

- **Load-time:** `COPY INTO` uses `ON_ERROR = 'ABORT_STATEMENT'` by
  default in the scripts — a malformed row fails the whole batch rather
  than silently skipping bad data. (Trade-off: no partial loads, but no
  silent data loss either — documented here as the deliberate choice.)
- **Transform-time:** dbt tests run via `dbt build`/`dbt test`, which
  fails the pipeline (non-zero exit code) if any test fails — this is
  the DQ gate before data is considered "in the mart."
- **No dead-letter queue / quarantine table** is implemented for rejected
  rows — a known simplification, noted as backlog.

---

## 11. Execution / Run Order

```
1. snowflake_setup/01_setup_database.sql      (one-time)
2. snowflake_setup/02_stage_and_fileformat.sql (one-time)
3. snowflake_setup/03_raw_tables.sql           (one-time)
4. Load accounts_day1.csv, customers.csv, branches.csv, transactions_batch1.csv
5. snowflake_setup/04_copy_into.sql            (batch 1)
6. dbt seed                                    (channel_lookup)
7. dbt snapshot                                (captures day1 account state)
8. dbt run --select staging+                   (staging → intermediate → marts, batch 1 data)
9. Load accounts_day2.csv, transactions_batch2.csv
10. snowflake_setup/04_copy_into.sql           (batch 2)
11. dbt snapshot                               (captures day2 changes → SCD2 versioning happens here)
12. dbt run                                    (fct_transactions picks up batch 2 incrementally)
13. dbt test                                   (all 38 tests)
14. dbt docs generate && dbt docs serve         (lineage graph)
```

This exact ordering — snapshot *before* the day2 transformation run — is
what makes the SCD2 demo work; running it out of order means the
snapshot never sees the "before" state to version against.
