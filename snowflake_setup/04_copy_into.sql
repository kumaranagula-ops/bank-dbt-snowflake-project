-- ============================================================================
-- 04_copy_into.sql
-- Loads the sample CSVs from the stage into RAW tables.
-- Run 03_raw_tables.sql first. Upload the CSVs to the stage before running this.
-- ============================================================================
USE DATABASE BANK_DB;
USE SCHEMA RAW;

-- Static reference data
COPY INTO RAW_BRANCHES
  FROM @BANK_INTERNAL_STAGE/branches.csv
  FILE_FORMAT = (FORMAT_NAME = CSV_STANDARD)
  ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW_CUSTOMERS
  FROM @BANK_INTERNAL_STAGE/customers.csv
  FILE_FORMAT = (FORMAT_NAME = CSV_STANDARD)
  ON_ERROR = 'ABORT_STATEMENT';

-- Accounts: load DAY 1 file first -> this is the state the first dbt snapshot
-- run will capture as the initial SCD2 record for every account.
COPY INTO RAW_ACCOUNTS
  FROM @BANK_INTERNAL_STAGE/accounts_day1.csv
  FILE_FORMAT = (FORMAT_NAME = CSV_STANDARD)
  ON_ERROR = 'ABORT_STATEMENT';

-- -----------------------------------------------------------------------
-- >>> After this first load: run `dbt snapshot` once (captures v1 state) <<<
-- -----------------------------------------------------------------------
-- Then simulate "next day's" changed accounts feed:
--   TRUNCATE TABLE RAW_ACCOUNTS;
--   COPY INTO RAW_ACCOUNTS FROM @BANK_INTERNAL_STAGE/accounts_day2.csv
--     FILE_FORMAT = (FORMAT_NAME = CSV_STANDARD);
--   Then run `dbt snapshot` again -> dbt closes out changed records (valid_to
--   populated) and inserts new current rows, giving you full SCD2 history.

-- Transactions batch 1 (initial/full load — 40,000 rows)
COPY INTO RAW_TRANSACTIONS (transaction_id, account_id, txn_date, txn_type, amount, channel, created_at)
  FROM @BANK_INTERNAL_STAGE/transactions_batch1.csv
  FILE_FORMAT = (FORMAT_NAME = CSV_STANDARD)
  ON_ERROR = 'ABORT_STATEMENT';

-- -----------------------------------------------------------------------
-- >>> After this: run `dbt run --select stg_transactions+` to build the
--     incremental model on the first 40k rows. <<<
-- -----------------------------------------------------------------------

-- Transactions batch 2 (incremental/delta load — 10,000 new rows, later dates)
-- This models a NEW file landing in S3 that your pipeline picks up next run.
COPY INTO RAW_TRANSACTIONS (transaction_id, account_id, txn_date, txn_type, amount, channel, created_at)
  FROM @BANK_INTERNAL_STAGE/transactions_batch2.csv
  FILE_FORMAT = (FORMAT_NAME = CSV_STANDARD)
  ON_ERROR = 'ABORT_STATEMENT';

-- -----------------------------------------------------------------------
-- >>> Re-run `dbt run --select stg_transactions+` — the incremental model
--     will MERGE only the new 10,000 rows in, not reprocess all 50,000. <<<
-- -----------------------------------------------------------------------

-- Sanity check
SELECT 'RAW_BRANCHES' AS tbl, COUNT(*) FROM RAW_BRANCHES
UNION ALL SELECT 'RAW_CUSTOMERS', COUNT(*) FROM RAW_CUSTOMERS
UNION ALL SELECT 'RAW_ACCOUNTS', COUNT(*) FROM RAW_ACCOUNTS
UNION ALL SELECT 'RAW_TRANSACTIONS', COUNT(*) FROM RAW_TRANSACTIONS;
