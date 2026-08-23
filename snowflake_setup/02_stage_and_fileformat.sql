-- ============================================================================
-- 02_stage_and_fileformat.sql
-- Creates the CSV file format and the S3 external stage.
-- ============================================================================
USE DATABASE BANK_DB;
USE SCHEMA RAW;

-- File format matching the sample CSVs (header row, comma-delimited)
CREATE OR REPLACE FILE FORMAT CSV_STANDARD
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE
  DATE_FORMAT = 'AUTO'
  TIMESTAMP_FORMAT = 'AUTO';

-- ----------------------------------------------------------------------------
-- OPTION A: Storage Integration (recommended, no hardcoded keys)
-- Requires an IAM role trust relationship set up in AWS first.
-- ----------------------------------------------------------------------------
-- CREATE STORAGE INTEGRATION BANK_S3_INT
--   TYPE = EXTERNAL_STAGE
--   STORAGE_PROVIDER = 'S3'
--   ENABLED = TRUE
--   STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>'
--   STORAGE_ALLOWED_LOCATIONS = ('s3://<your-bucket>/bank_savings/');
--
-- -- Then run DESC INTEGRATION BANK_S3_INT; and update the AWS role's trust
-- -- policy with the STORAGE_AWS_IAM_USER_ARN / STORAGE_AWS_EXTERNAL_ID it returns.
--
-- CREATE STAGE BANK_S3_STAGE
--   URL = 's3://<your-bucket>/bank_savings/'
--   STORAGE_INTEGRATION = BANK_S3_INT
--   FILE_FORMAT = CSV_STANDARD;

-- ----------------------------------------------------------------------------
-- OPTION B: Quick-start with an internal stage (no AWS setup needed)
-- Use this to test the pipeline end-to-end today; swap to Option A for real S3.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE STAGE BANK_INTERNAL_STAGE
  FILE_FORMAT = CSV_STANDARD;

-- Upload sample files via SnowSQL or Snowsight "Load Data" UI, e.g.:
--   snowsql -q "PUT file:///path/to/sample_data/*.csv @BANK_DB.RAW.BANK_INTERNAL_STAGE"
-- Or drag-and-drop through Snowsight: Data > Databases > BANK_DB > RAW > Stages
