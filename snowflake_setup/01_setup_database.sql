-- ============================================================================
-- 01_setup_database.sql
-- Bank Savings Account project - Snowflake environment bootstrap
-- Run as ACCOUNTADMIN or a role with CREATE DATABASE/WAREHOUSE privileges
-- ============================================================================

-- Warehouse (XS is plenty for 50k rows; suspend fast to control cost)
CREATE WAREHOUSE IF NOT EXISTS BANK_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- Database
CREATE DATABASE IF NOT EXISTS BANK_DB;

USE DATABASE BANK_DB;

-- Schemas: raw (landing/bronze), analytics (dbt models will build into this)
CREATE SCHEMA IF NOT EXISTS RAW;      -- raw loaded CSVs land here
CREATE SCHEMA IF NOT EXISTS ANALYTICS; -- dbt target schema (staging/int/marts)

-- Dedicated role for this project (optional but good practice)
CREATE ROLE IF NOT EXISTS BANK_DBT_ROLE;
GRANT USAGE ON WAREHOUSE BANK_WH TO ROLE BANK_DBT_ROLE;
GRANT ALL ON DATABASE BANK_DB TO ROLE BANK_DBT_ROLE;
GRANT ALL ON SCHEMA BANK_DB.RAW TO ROLE BANK_DBT_ROLE;
GRANT ALL ON SCHEMA BANK_DB.ANALYTICS TO ROLE BANK_DBT_ROLE;
GRANT ALL ON ALL TABLES IN SCHEMA BANK_DB.RAW TO ROLE BANK_DBT_ROLE;

-- Assign role to your user (replace <YOUR_USER>)
-- GRANT ROLE BANK_DBT_ROLE TO USER <YOUR_USER>;

USE WAREHOUSE BANK_WH;
USE SCHEMA BANK_DB.RAW;
