# High-Level Design (HLD)
### Bank Savings Account Data Platform — dbt + Snowflake

| | |
|---|---|
| **Document Owner** | Kumara Nagula |
| **Status** | Baseline (v1.0) |
| **Project Type** | Batch data warehouse / analytics engineering |
| **Related Docs** | `docs/ER_DIAGRAM.md`, `docs/SPRINT_PLAN.md`, `docs/LLD.md` |

---

## 1. Purpose & Scope

Build a cloud-native data warehouse for a retail bank's savings account
line of business, replacing a conceptual legacy ETL (Informatica-style)
approach with an ELT pattern on Snowflake using dbt for transformation.

**In scope:** customer, branch, account, and transaction data; account
history (SCD2); daily/batch transaction loads; a curated mart layer for
reporting.

**Out of scope (see backlog in `docs/SPRINT_PLAN.md`):** real-time
streaming ingestion, CDC via Streams/Tasks, multi-region DR, a BI
semantic layer, and orchestration tooling (Airflow/Jenkins) — this project
runs jobs manually/CLI-triggered rather than on a schedule.

## 2. Business Context

| Stakeholder | Need |
|---|---|
| Branch operations | Accurate current balances and account status per branch |
| Compliance / audit | Full history of account status and interest-rate changes (regulatory traceability) |
| Finance / analytics | Monthly transaction volume and balance trends per account |
| Data engineering | A maintainable, testable pipeline that can scale from 50K to millions of transactions without a redesign |

## 3. Architecture Overview

**Pattern:** ELT (Extract-Load-Transform) — raw data is loaded into
Snowflake first, then transformed in-warehouse with dbt. This is the
modern equivalent of what Informatica/IDMC does with in-flight
transformation (ETL); the shift to ELT is itself a talking point for the
legacy-to-cloud transition this project is meant to demonstrate.

```
┌───────────────┐     ┌───────────────┐     ┌────────────────────────────────┐
│  Source        │     │  Landing /    │     │            Snowflake            │
│  Systems       │────▶│  Staging      │────▶│  ┌─────────┐    ┌────────────┐  │
│ (core banking, │     │  (S3 bucket / │     │  │  RAW    │───▶│  ANALYTICS │  │
│  CSV extracts) │     │  internal     │     │  │ schema  │    │  schema    │  │
└───────────────┘     │  stage)       │     │  └─────────┘    └────────────┘  │
                       └───────────────┘     │       ▲               ▲        │
                                              │       │               │        │
                                              │   COPY INTO       dbt (ELT)    │
                                              └─────────────────────────────────┘
                                                                     │
                                                          ┌──────────▼──────────┐
                                                          │  Consumption layer  │
                                                          │  (BI tools, ad hoc  │
                                                          │  SQL, dbt docs)     │
                                                          └─────────────────────┘
```

### 3.1 Layered zones inside Snowflake

| Zone | Schema | Purpose | Materialization |
|---|---|---|---|
| Landing | `RAW` | 1:1 mirror of source files, minimal typing, append/overwrite | Native tables |
| Staging | `ANALYTICS` (views) | Typed, renamed, lightly cleaned; 1:1 with raw | Views |
| Intermediate | `ANALYTICS` | Business logic (enrichment, running balances) not meant for direct consumption | Ephemeral (compiled inline, no physical object) |
| Marts | `ANALYTICS` | Conformed dimensions, fact table, aggregates — the consumption layer | Table / Incremental / Snapshot |

## 4. Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| Cloud data warehouse | Snowflake | Separates storage/compute, native semi-structured support, zero-copy cloning, time travel — no index/tuning overhead vs. traditional RDBMS |
| Transformation | dbt Core | SQL-first, version-controlled, testable, generates lineage docs automatically; industry-standard replacement for stored-proc or Informatica mapping-based transformation |
| Source data generation | Python (Faker) | Synthetic data generation for a repeatable dev/test dataset |
| Ingestion | Snowflake `COPY INTO` / internal + external (S3) stages | Bulk load pattern; production equivalent would add Snowpipe for continuous load |
| Version control | Git | Full history, `.gitignore` excludes credentials/build artifacts |
| Testing | dbt generic + singular tests, `dbt_utils`, `dbt_expectations` | Data quality gates before data reaches the mart layer |

## 5. Data Flow (Level 0)

1. Source extracts (branches, customers, accounts, transactions) land as
   CSV in an S3 bucket or internal stage.
2. `COPY INTO` bulk-loads files into `RAW.*` tables — no transformation,
   schema mirrors source.
3. dbt `staging` views apply typing, casing, and column renames — the
   contract boundary between raw and everything downstream.
4. dbt `intermediate` (ephemeral) models apply business logic: account
   enrichment, running balance via window function.
5. dbt `snapshots` capture point-in-time account state changes (SCD2).
6. dbt `marts` produce the final dimensional model: `dim_customers`,
   `dim_branches`, `dim_accounts_scd2`, `fct_transactions` (incremental),
   `mart_account_monthly_summary` (aggregate).
7. Consumption: BI tools or ad hoc SQL query the `ANALYTICS` schema
   directly; `dbt docs generate` produces a browsable lineage graph.

See `docs/ER_DIAGRAM.md` §5 for the full source-to-mart lineage diagram.

## 6. Key Design Decisions

| Decision | Alternative considered | Why this choice |
|---|---|---|
| ELT on Snowflake + dbt | ETL via Informatica IDMC | Cloud-native, git-based, cheaper to test/iterate; matches current industry direction |
| SCD Type 2 via dbt snapshot | Manual merge logic in a model | Snapshots are dbt's purpose-built, well-tested mechanism for this; less custom code to maintain |
| Incremental `merge` strategy on `fct_transactions` | Full-refresh table | At 50K rows full-refresh is fine, but the design must scale — merge avoids reprocessing the entire fact table every run |
| Clustering key (`txn_date_key`) instead of an index | N/A — Snowflake has no user-managed indexes | Snowflake auto-partitions via micro-partitions; clustering is the only user lever to influence pruning |
| Ephemeral intermediate models | Materialized tables | No downstream consumer needs these directly; ephemeral avoids storage cost and clutter in the warehouse |

## 7. Non-Functional Requirements

| Category | Requirement | How addressed |
|---|---|---|
| Scalability | Design must not require rework if transaction volume grows 100x | Incremental fact + clustering key; RAW/staging/marts separation allows independent scaling |
| Data quality | No bad data reaches the mart layer undetected | 38 dbt tests (not_null, unique, relationships, accepted_range, custom singular test) gating the build |
| Auditability | Regulatory need to reconstruct historical account state | SCD2 snapshot with `valid_from`/`valid_to`/`is_current` |
| Cost control | Avoid idle compute spend | Warehouse auto-suspend/auto-resume; incremental models avoid full-table reprocessing |
| Maintainability | New engineer should onboard without tribal knowledge | dbt docs + lineage graph, README, this HLD/LLD, ER diagram |
| Security | Credentials never in source control | `.gitignore` excludes `profiles.yml`/credentials; storage integration (IAM role) preferred over embedded S3 keys |

## 8. Security & Access Model

- Snowflake role `BANK_DBT_ROLE` scoped to `BANK_DB` only — least privilege.
- S3 access via storage integration (IAM role delegation), not embedded
  access keys — avoids long-lived credentials being exposed via `SHOW
  STAGES`.
- No PII masking is implemented in this scaled-down build (`email`,
  `phone`, `address` flow through as-is); a production version would add
  Snowflake dynamic data masking or column-level security on `dim_customers`.
  Called out explicitly here as a known gap, not an oversight — good to
  raise proactively in an interview.

## 9. Deployment View (target, not yet automated)

```
Developer laptop / Claude Code
        │  git push
        ▼
   Git repository
        │  CI trigger (future: GitHub Actions / Jenkins)
        ▼
  dbt build --target prod
        │
        ▼
  Snowflake (BANK_DB.ANALYTICS)
```

Currently this project runs via manual CLI (`dbt build`) against a dev
target. CI/CD is listed as backlog in `docs/SPRINT_PLAN.md` §"Future
Sprints."

## 10. Risks & Assumptions

- **Assumption:** source extracts arrive as clean, well-formed CSVs. No
  malformed-file handling / dead-letter queue is built.
- **Risk:** two-batch transaction load (40K + 10K) is a simplification of
  what would really be a continuous or daily feed; production would need
  Snowpipe or a scheduler, not manual `COPY INTO` runs.
- **Risk:** no environment separation (dev/QA/prod) is implemented — one
  schema. Production design would use Snowflake zero-copy cloning per
  environment.
