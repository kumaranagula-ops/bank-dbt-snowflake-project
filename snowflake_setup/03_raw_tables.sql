-- ============================================================================
-- 03_raw_tables.sql
-- Raw ("bronze") tables — structure mirrors the source CSVs 1:1, minimal typing.
-- dbt sources.yml points at these.
-- ============================================================================
USE DATABASE BANK_DB;
USE SCHEMA RAW;

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

-- Loaded twice (day1 / day2) to feed the dbt snapshot demonstrating SCD Type 2
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
