-- ============================================================================
-- 05_security_roles_masking.sql
-- Bank Savings Account project - Roles, Dynamic Data Masking, Row Access Policy
-- Run as ACCOUNTADMIN (role creation, policy creation/attachment need elevated rights)
-- ============================================================================

USE DATABASE BANK_DB;
USE SCHEMA ANALYTICS;

-- ----------------------------------------------------------------------------
-- STEP 1: Roles
-- Three roles to mirror a real bank: a teller who should never see full PII,
-- a branch manager who should only see their own branch's rows, and an
-- analyst/auditor who can see everything for reporting.
-- ----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS BANK_TELLER;
CREATE ROLE IF NOT EXISTS BANK_BRANCH_MANAGER;
CREATE ROLE IF NOT EXISTS BANK_ANALYST;

-- All three need to actually run queries, so give them warehouse + read access
GRANT USAGE ON WAREHOUSE BANK_WH TO ROLE BANK_TELLER;
GRANT USAGE ON WAREHOUSE BANK_WH TO ROLE BANK_BRANCH_MANAGER;
GRANT USAGE ON WAREHOUSE BANK_WH TO ROLE BANK_ANALYST;

GRANT USAGE ON DATABASE BANK_DB TO ROLE BANK_TELLER;
GRANT USAGE ON DATABASE BANK_DB TO ROLE BANK_BRANCH_MANAGER;
GRANT USAGE ON DATABASE BANK_DB TO ROLE BANK_ANALYST;

GRANT USAGE ON SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_TELLER;
GRANT USAGE ON SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_BRANCH_MANAGER;
GRANT USAGE ON SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_ANALYST;

GRANT SELECT ON ALL TABLES IN SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_TELLER;
GRANT SELECT ON ALL TABLES IN SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_BRANCH_MANAGER;
GRANT SELECT ON ALL TABLES IN SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_ANALYST;

-- Assign roles to your user to test (replace <YOUR_USER>)
-- GRANT ROLE BANK_TELLER TO USER <YOUR_USER>;
-- GRANT ROLE BANK_BRANCH_MANAGER TO USER <YOUR_USER>;
-- GRANT ROLE BANK_ANALYST TO USER <YOUR_USER>;

-- ----------------------------------------------------------------------------
-- STEP 2: Dynamic Data Masking on dim_customers PII
-- Teller sees masked email/phone/dob. Analyst and Branch Manager see full
-- values (branch manager still gets row-restricted separately in Step 3).
-- ----------------------------------------------------------------------------

-- Email: teller sees only the domain, e.g. '***@gmail.com'
CREATE OR REPLACE MASKING POLICY mask_email AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('BANK_ANALYST', 'BANK_BRANCH_MANAGER', 'ACCOUNTADMIN') THEN val
    ELSE '***@' || SPLIT_PART(val, '@', -1)
  END;

-- Phone: teller sees only last 4 digits
CREATE OR REPLACE MASKING POLICY mask_phone AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('BANK_ANALYST', 'BANK_BRANCH_MANAGER', 'ACCOUNTADMIN') THEN val
    ELSE 'XXXXXX' || RIGHT(val, 4)
  END;

-- Date of birth: teller sees NULL entirely
CREATE OR REPLACE MASKING POLICY mask_dob AS (val DATE) RETURNS DATE ->
  CASE
    WHEN CURRENT_ROLE() IN ('BANK_ANALYST', 'BANK_BRANCH_MANAGER', 'ACCOUNTADMIN') THEN val
    ELSE NULL
  END;

-- Attach the policies to the actual columns on dim_customers
ALTER TABLE dim_customers MODIFY COLUMN email    SET MASKING POLICY mask_email;
ALTER TABLE dim_customers MODIFY COLUMN phone    SET MASKING POLICY mask_phone;
ALTER TABLE dim_customers MODIFY COLUMN dob      SET MASKING POLICY mask_dob;

-- ----------------------------------------------------------------------------
-- STEP 3: Row Access Policy on dim_accounts_scd2
-- Branch manager should only see rows for their own branch. We simulate
-- "their own branch" with a session variable set at login (in real prod this
-- would come from a mapping table of user -> branch_id).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE ROW ACCESS POLICY branch_rap AS (branch_id_col NUMBER)
  RETURNS BOOLEAN ->
    CASE
      WHEN CURRENT_ROLE() IN ('BANK_ANALYST', 'ACCOUNTADMIN') THEN TRUE  -- see all branches
      WHEN CURRENT_ROLE() = 'BANK_BRANCH_MANAGER'
           AND branch_id_col = TO_NUMBER(GETVARIABLE('MY_BRANCH_ID')) THEN TRUE
      ELSE FALSE
    END;

ALTER TABLE dim_accounts_scd2 ADD ROW ACCESS POLICY branch_rap ON (branch_id);

-- ----------------------------------------------------------------------------
-- STEP 4: How to test as a branch manager
-- GETVARIABLE reads a SQL variable set with SET (not a session parameter, so
-- it is NOT set via ALTER SESSION SET). Set it like this before querying:
-- ----------------------------------------------------------------------------
-- USE ROLE BANK_BRANCH_MANAGER;
-- SET MY_BRANCH_ID = '3';                  -- pretend this manager owns branch 3
-- SELECT * FROM dim_accounts_scd2;         -- only branch_id = 3 rows come back
--
-- Note: in real production, "MY_BRANCH_ID" would come from a mapping table of
-- user -> branch_id (looked up via CURRENT_USER() inside the policy) rather
-- than a manually-set session variable, since you can't trust every client
-- tool to set it correctly. The mapping-table pattern is the more realistic
-- interview answer; the session variable here is just the quickest way to
-- demo and test the row access policy behavior yourself.

-- ----------------------------------------------------------------------------
-- STEP 5: Production-realistic version - mapping table instead of session var
-- This is the version to describe in an interview: no reliance on a client
-- tool remembering to SET a variable, the policy looks up the logged-in
-- user's branch automatically via CURRENT_USER().
-- ----------------------------------------------------------------------------

-- One row per branch manager: which Snowflake login maps to which branch
CREATE TABLE IF NOT EXISTS branch_manager_mapping (
    snowflake_username STRING,
    branch_id           NUMBER
);

-- Example rows (replace with real usernames)
-- INSERT INTO branch_manager_mapping VALUES ('JSMITH', 3), ('RPATEL', 7);

CREATE OR REPLACE ROW ACCESS POLICY branch_rap_mapped AS (branch_id_col NUMBER)
  RETURNS BOOLEAN ->
    CASE
      WHEN CURRENT_ROLE() IN ('BANK_ANALYST', 'ACCOUNTADMIN') THEN TRUE
      WHEN CURRENT_ROLE() = 'BANK_BRANCH_MANAGER'
           AND EXISTS (
             SELECT 1 FROM branch_manager_mapping m
             WHERE m.snowflake_username = CURRENT_USER()
               AND m.branch_id = branch_id_col
           ) THEN TRUE
      ELSE FALSE
    END;

-- Swap the demo policy for this one (a table can only have one row access
-- policy attached at a time, so drop the session-variable version first):
-- ALTER TABLE dim_accounts_scd2 DROP ROW ACCESS POLICY branch_rap;
-- ALTER TABLE dim_accounts_scd2 ADD ROW ACCESS POLICY branch_rap_mapped ON (branch_id);
--
-- With this version, a branch manager just logs in and queries normally,
-- no SET command needed, the policy looks them up by CURRENT_USER() against
-- the mapping table on every query.
--
-- USE ROLE BANK_TELLER;
-- SELECT customer_id, email, phone, dob FROM dim_customers;  -- masked values
--
-- USE ROLE BANK_ANALYST;
-- SELECT customer_id, email, phone, dob FROM dim_customers;  -- full values
