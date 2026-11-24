-- 02_objects.sql  : run AFTER Azure step 6 (consent + RBAC)
-- Reuses existing LEARNING_DB.DEMO and SNOWFLAKE_LEARNING_WH (owned by ACCOUNTADMIN)
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

CREATE FILE FORMAT IF NOT EXISTS SFDC_PARQUET_FF
  TYPE = PARQUET
  COMPRESSION = AUTO           -- snappy / gzip / etc. detected automatically
  BINARY_AS_TEXT = FALSE
  USE_LOGICAL_TYPE = TRUE      -- honour Parquet logical types (timestamps, decimals)
  COMMENT = 'Salesforce Parquet extracts';

CREATE STAGE IF NOT EXISTS SFDC_ADLS_STAGE
  URL = 'azure://jominsdevadls.blob.core.windows.net/salesforce-raw/'
  STORAGE_INTEGRATION = SFDC_ADLS_STORAGE_INT
  FILE_FORMAT = SFDC_PARQUET_FF
  COMMENT = 'ADLS Gen2 landing container for Salesforce Parquet';

-- Smoke test: should return without an auth error (empty until files are uploaded)
LIST @SFDC_ADLS_STAGE;
