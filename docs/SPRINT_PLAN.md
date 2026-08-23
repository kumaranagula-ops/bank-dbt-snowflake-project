# Sprint Plan — Bank Savings Account dbt + Snowflake Pipeline

This project is scoped and sequenced the way a real 2-week-sprint data
engineering team would run it. Even though it was built solo, breaking it
into sprints with stories/acceptance criteria/points is useful for two
reasons: it forces you to think in dependency order (you can't build a
mart before staging exists), and it gives you a ready-made way to talk
through "how did you plan and execute this" in an interview instead of
just describing the finished artifact.

Story points are rough (Fibonacci: 1, 2, 3, 5, 8), assuming a single
engineer. Total: **~34 points across 5 sprints**.

---

## Sprint 0 — Environment & Foundations (3 pts)

**Goal:** Nothing is buildable until the warehouse, database, roles, and
file formats exist.

| Story | Points | Acceptance Criteria | Artifact |
|---|---|---|---|
| As an engineer, I need a dedicated warehouse/database/schema/role so dev work is isolated from other workloads | 1 | `BANK_WH`, `BANK_DB`, `RAW`/`ANALYTICS` schemas, `BANK_DBT_ROLE` created and grantable | `snowflake_setup/01_setup_database.sql` |
| As an engineer, I need a file format and staging area so CSVs can be loaded | 1 | `CSV_STANDARD` file format defined; internal stage created; S3 external stage template ready | `snowflake_setup/02_stage_and_fileformat.sql` |
| As an engineer, I need raw table DDL matching the source data shape | 1 | 4 raw tables created (`RAW_BRANCHES`, `RAW_CUSTOMERS`, `RAW_ACCOUNTS`, `RAW_TRANSACTIONS`) | `snowflake_setup/03_raw_tables.sql` |

---

## Sprint 1 — Source Data & Ingestion (5 pts)

**Goal:** Realistic, referentially-consistent synthetic data exists and can
be loaded, including a "day 2" delta to exercise SCD2 later.

| Story | Points | Acceptance Criteria | Artifact |
|---|---|---|---|
| As an analyst, I need realistic branch/customer/account/transaction data to test against | 3 | 8 branches, 3,000 customers, 3,500 accounts, 50,000 transactions across 2 batches, referential integrity holds | `sample_data/generate_data.py` |
| As an engineer, I need a "day 2" account snapshot with deliberate changes | 1 | 400 accounts mutate status/interest rate between day1 and day2 (SCD2 test fixture) | `sample_data/accounts_day2.csv` |
| As an engineer, I need repeatable COPY INTO scripts | 1 | Idempotent load scripts, documented run order between batches | `snowflake_setup/04_copy_into.sql` |

---

## Sprint 2 — Staging Layer (5 pts)

**Goal:** 1:1 typed views over raw, with source freshness checks and basic
data quality tests — the contract layer between raw and everything else.

| Story | Points | Acceptance Criteria | Artifact |
|---|---|---|---|
| As an engineer, I need typed staging views so downstream models never touch RAW directly | 3 | 4 staging views (`stg_branches`, `stg_customers`, `stg_accounts`, `stg_transactions`), consistent naming/casting | `models/staging/*.sql` |
| As a data steward, I need source freshness monitoring and column-level tests | 2 | `_sources.yml` with freshness config; not_null/unique/accepted_values/relationships tests passing | `models/staging/_sources.yml`, `_staging_models.yml` |

---

## Sprint 3 — Intermediate & Core Marts (8 pts)

**Goal:** Business logic layer (ephemeral) plus the Type 1 dimensions and
the SCD2 account history.

| Story | Points | Acceptance Criteria | Artifact |
|---|---|---|---|
| As an analyst, I need enriched account and running-balance logic isolated from raw joins | 3 | Ephemeral `int_accounts_enriched`, `int_transactions_with_balance` (window function) compile cleanly into downstream models | `models/intermediate/*.sql` |
| As an analyst, I need conformed customer and branch dimensions | 2 | `dim_customers`, `dim_branches` built, tested unique/not_null on PK | `models/marts/dim_customers.sql`, `dim_branches.sql` |
| As a compliance/audit stakeholder, I need full history of account status and interest rate changes | 3 | `accounts_snapshot` (timestamp strategy) + `dim_accounts_scd2` correctly version rows on the day2 delta; `is_current` flag validated | `snapshots/accounts_snapshot.sql`, `models/marts/dim_accounts_scd2.sql` |

---

## Sprint 4 — Fact Table & Performance (5 pts)

**Goal:** The transaction fact table needs to scale — incremental
processing, not full-refresh, and clustered for query performance.

| Story | Points | Acceptance Criteria | Artifact |
|---|---|---|---|
| As an engineer, I need `fct_transactions` to process only new batches, not reload 50k rows every run | 3 | Incremental model, `merge` strategy, watermark on `txn_date`, `is_incremental()` guard verified against batch 2 | `models/marts/fct_transactions.sql` |
| As a query consumer, I need transaction queries filtered by date to be fast at scale | 1 | `cluster_by=['txn_date_key']` applied; documented rationale | `models/marts/fct_transactions.sql` |
| As an analyst, I need a pre-aggregated monthly summary so BI tools don't scan the full fact table | 1 | `mart_account_monthly_summary` grain = account x month, reconciles to `fct_transactions` | `models/marts/mart_account_monthly_summary.sql` |

---

## Sprint 5 — Testing, Documentation & Hardening (8 pts)

**Goal:** Make it production-credible — tests that catch real bugs, docs a
new teammate could onboard from, packages/macros that reduce repetition,
and a clean handoff.

| Story | Points | Acceptance Criteria | Artifact |
|---|---|---|---|
| As a data quality owner, I need generic + singular tests across the whole DAG | 3 | 38 data tests passing (`dbt_utils`, `dbt_expectations`, custom singular test for negative balances) | `tests/`, `_marts_models.yml` |
| As an engineer, I need reusable macros instead of copy-pasted SQL | 1 | `calculate_annual_interest`, `set_query_tag` macros in use | `macros/*.sql` |
| As a new team member, I need docs + an ER diagram + a run order so I can onboard without a Slack thread | 2 | README with topic-mapping tables, run order, `dbt docs generate` clean | `README.md`, `docs/ER_DIAGRAM.md` |
| As a reviewer, I need the project to parse/build cleanly with zero errors before merge | 2 | `dbt parse --no-partial-parse` → 0 errors, 0 warnings across 11 models, 1 snapshot, 38 tests, 1 seed, 4 sources | validated in this session |

---

## Backlog / Future Sprints (not built — stated scope boundary)

These were explicitly called out in the README as "account-level or ad hoc"
features, not part of this sprint scope. Good to mention if an interviewer
asks "what would you do next":

- **Sprint 6 candidate:** Streams + Tasks for CDC-driven, event-triggered
  incremental loads instead of scheduled batch runs.
- **Sprint 6 candidate:** Time Travel / zero-copy clone demo for
  dev/QA environment provisioning without physical data copies.
- **Sprint 7 candidate:** Real S3 external stage via storage integration
  (currently templated, not connected to a live bucket).
- **Sprint 7 candidate:** CI/CD via GitHub Actions or Jenkins — run
  `dbt build` + `sqlfluff` lint on every PR.

---

## How to use this in an interview

If asked "walk me through how you'd plan this project," don't just recite
the sprint table — narrate the *dependency logic*: raw tables must exist
before staging, staging before intermediate, intermediate before marts,
and the SCD2 snapshot has to run *between* the day1 and day2 account loads
or there's nothing to version. That ordering constraint is the real
answer to "why sprint it this way," not just "because agile."
