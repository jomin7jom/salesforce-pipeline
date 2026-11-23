-- 03_table_and_pipe.sql  : run AFTER uploading >=1 sample file to salesforce-raw/account/
-- Repeat this file per Salesforce object (replace ACCOUNT / account/).
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

-- Preview what Snowflake infers from the Parquet schema
SELECT *
FROM TABLE(INFER_SCHEMA(
  LOCATION    => '@SFDC_ADLS_STAGE/account/',
  FILE_FORMAT => 'SFDC_PARQUET_FF',
  IGNORE_CASE => TRUE));

-- Create the table from the inferred columns, plus audit columns
CREATE TABLE IF NOT EXISTS SFDC_ACCOUNT_RAW
  USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) WITHIN GROUP (ORDER BY ORDER_ID)
    FROM TABLE(INFER_SCHEMA(
      LOCATION    => '@SFDC_ADLS_STAGE/account/',
      FILE_FORMAT => 'SFDC_PARQUET_FF',
      IGNORE_CASE => TRUE)))
  ENABLE_SCHEMA_EVOLUTION = TRUE;   -- new Salesforce fields get added automatically

ALTER TABLE SFDC_ACCOUNT_RAW ADD COLUMN IF NOT EXISTS _SRC_FILE  VARCHAR;
ALTER TABLE SFDC_ACCOUNT_RAW ADD COLUMN IF NOT EXISTS _LOADED_AT TIMESTAMP_LTZ;

-- Auto-ingest pipe, scoped to the account/ folder only
CREATE PIPE IF NOT EXISTS SFDC_ACCOUNT_PIPE
  AUTO_INGEST = TRUE
  INTEGRATION = 'SFDC_ADLS_NOTIFICATION_INT'
  COMMENT = 'Salesforce Account Parquet -> DEMO.SFDC_ACCOUNT_RAW'
AS
COPY INTO SFDC_ACCOUNT_RAW
FROM @SFDC_ADLS_STAGE/account/
FILE_FORMAT = (FORMAT_NAME = 'SFDC_PARQUET_FF')
PATTERN = '.*[.]parquet'            -- skip the zero-byte ADLS Gen2 directory entries
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (_SRC_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME)
ON_ERROR = 'SKIP_FILE';

-- Load files that arrived before the pipe existed (only looks back 7 days)
ALTER PIPE SFDC_ACCOUNT_PIPE REFRESH;
