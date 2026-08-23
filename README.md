# Bank Savings Account — dbt + Snowflake End-to-End Project

A minimal but complete pipeline: S3-style CSV source → Snowflake raw tables →
dbt staging → intermediate → marts, with SCD2 history, incremental loads,
tests, docs, and Snowflake-specific performance config. 50,000 transaction
records across ~3,500 accounts / 3,000 customers / 8 branches.

📐 Full ER diagrams (raw + mart layer, Mermaid) and lineage: [`docs/ER_DIAGRAM.md`](docs/ER_DIAGRAM.md)
🗂️ Sprint-by-sprint build plan with user stories/acceptance criteria: [`docs/SPRINT_PLAN.md`](docs/SPRINT_PLAN.md)
🏗️ High-Level Design (architecture, tech stack, NFRs, security): [`docs/HLD.md`](docs/HLD.md)
🔧 Low-Level Design (schemas, transformation logic, test inventory): [`docs/LLD.md`](docs/LLD.md)

## Data model

```
branches (8)  ──┐
                 ├──< accounts (3,500) ──< transactions (50,000)
customers (3,000)┘
```

- `branches` — static reference dimension
- `customers` — one row per customer
- `accounts` — one row per savings account (snapshotted for SCD2: interest
  rate changes, status changes)
- `transactions` — append-only ledger (loaded in two batches: 40k + 10k, to
  demonstrate incremental loading)

## Run order

1. **Snowflake setup** (`snowflake_setup/`, run in order 01 → 04)
   - `01_setup_database.sql` — warehouse, database, schemas, role
   - `02_stage_and_fileformat.sql` — file format + stage (internal stage for
     quick-start; storage integration template for real S3)
   - `03_raw_tables.sql` — raw table DDL
   - `04_copy_into.sql` — loads `sample_data/*.csv` into raw tables, with
     inline instructions on when to run `dbt snapshot` / `dbt run` between
     batches to see SCD2 and incremental loading in action

2. **Upload sample data to the stage** (internal stage quick-start):
   ```
   snowsql -q "PUT file:///path/to/sample_data/*.csv @BANK_DB.RAW.BANK_INTERNAL_STAGE AUTO_COMPRESS=TRUE"
   ```
   Or drag-and-drop in Snowsight: Data → BANK_DB → RAW → Stages → BANK_INTERNAL_STAGE.

3. **dbt setup**
   ```
   cd bank_dbt_project
   cp profiles_template.yml ~/.dbt/profiles.yml   # fill in your account/user
   dbt deps                                       # installs dbt_utils, dbt_expectations
   dbt seed                                       # loads channel_lookup.csv
   dbt snapshot                                   # captures accounts v1 (after loading accounts_day1.csv)
   dbt run                                        # builds staging → intermediate → marts
   dbt test                                       # runs all generic + singular tests
   dbt docs generate && dbt docs serve             # browsable lineage graph + column docs
   ```

4. **See incremental + SCD2 in action**: after step 3, in Snowflake truncate
   `RAW_ACCOUNTS` and load `accounts_day2.csv`, then `dbt snapshot` again —
   `dim_accounts_scd2` now shows two versions for ~400 changed accounts. Load
   `transactions_batch2.csv` and `dbt run --select fct_transactions` — only
   the new 10k rows get merged in, not all 50k.

## Topic coverage map

### dbt (20 topics → where they live)
| # | Topic | Where |
|---|-------|-------|
| 1 | Project structure (staging/int/marts) | `models/` folder layout |
| 2 | `ref()` / `source()` | every model, `_sources.yml` |
| 3 | Materializations (view/table/incremental/ephemeral) | `dbt_project.yml`, `fct_transactions.sql` |
| 4 | Incremental models + `is_incremental()` | `fct_transactions.sql` |
| 5 | Snapshots (SCD2) | `snapshots/accounts_snapshot.sql` |
| 6 | Generic tests | `_staging_models.yml`, `_marts_models.yml` |
| 7 | Singular/custom tests | `tests/assert_no_extreme_negative_balance.sql` |
| 8 | dbt_utils / dbt_expectations | `packages.yml`, `accepted_range`, `unique_combination_of_columns` |
| 9 | Jinja templating & macros | `macros/calculate_annual_interest.sql`, model configs |
| 10 | Variables (`vars`) | `dbt_project.yml` → `start_date` |
| 11 | Seeds | `seeds/channel_lookup.csv` |
| 12 | Clustering keys | `fct_transactions.sql` config `cluster_by` |
| 13 | Per-model warehouse sizing | `fct_transactions.sql` config `snowflake_warehouse` |
| 14 | Incremental strategies (merge) | `fct_transactions.sql` `incremental_strategy='merge'` |
| 15 | Query tagging | `macros/set_query_tag.sql` |
| 16 | Run/build commands & selectors | this README's run order |
| 17 | Documentation (`schema.yml`, `dbt docs`) | all `_*.yml` files |
| 18 | DAG/lineage | `dbt docs serve` after running |
| 19 | CI/CD | see note below — plug into Jenkins/GHEC like your other pipelines |
| 20 | Environments (dev/prod) | `profiles_template.yml` targets |

### Snowflake (20 topics → where they live)
| # | Topic | Where |
|---|-------|-------|
| 1 | Warehouses (sizing, auto-suspend/resume) | `01_setup_database.sql` |
| 2 | Databases & schemas | `01_setup_database.sql` |
| 3 | Roles & grants | `01_setup_database.sql` |
| 4 | File formats | `02_stage_and_fileformat.sql` |
| 5 | Internal stages | `02_stage_and_fileformat.sql` |
| 6 | External stages / storage integration (S3) | `02_stage_and_fileformat.sql` (commented template) |
| 7 | `COPY INTO` bulk loading | `04_copy_into.sql` |
| 8 | Table DDL & data types | `03_raw_tables.sql` |
| 9 | `MERGE` (via dbt incremental strategy) | `fct_transactions.sql` compiled SQL |
| 10 | Clustering keys | `fct_transactions.sql` |
| 11 | Query tagging & QUERY_HISTORY | `macros/set_query_tag.sql` |
| 12 | Time Travel (recover data) | see note below |
| 13 | Zero-copy cloning (dev/test envs) | see note below |
| 14 | Window functions | `int_transactions_with_balance.sql` |
| 15 | Semi-structured data readiness (VARIANT) | extendable — add a JSON txn metadata column |
| 16 | Streams & Tasks (CDC/automation) | see note below |
| 17 | Views vs tables (cost/perf tradeoff) | staging=views, marts=tables |
| 18 | Cost control (auto-suspend, XS warehouse) | `01_setup_database.sql` |
| 19 | Access control model (RBAC) | `BANK_DBT_ROLE` in `01_setup_database.sql` |
| 20 | Performance tuning (pruning via cluster keys) | `fct_transactions.sql` |

**Note on items marked "see note":** Time Travel, zero-copy cloning, and
Streams/Tasks aren't exercised by this project's SQL files since they're
account-level or ad hoc operational features rather than pipeline code —
but they're standard interview topics. Ask me for a walkthrough or
demo commands for any of them (e.g. `CREATE TABLE ... CLONE`, `AT(OFFSET => -3600)`,
or a `STREAM` + `TASK` pair that auto-triggers on new transaction files).

## Interview talking points this project gives you
- Full lineage story: raw CSV → Snowflake stage → COPY INTO → dbt transform → mart
- Real incremental design decision (merge on transaction_id, watermark on txn_date)
- Real SCD2 design decision (timestamp strategy, why interest_rate/status changes matter for a bank)
- Test strategy across three layers (source freshness, generic, singular)
- Cost-consciousness (XS warehouse, auto-suspend, per-model warehouse override, clustering)
