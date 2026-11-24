-- 09_opportunity_table_and_pipe.sql : run AFTER the first ADF run has written a file to
-- salesforce-opportunity-raw/opportunity/ (azure/03 step 4). Same pattern as 03_table_and_pipe.sql.
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

-- Preview what Snowflake infers from the Parquet schema
SELECT *
FROM TABLE(INFER_SCHEMA(
  LOCATION    => '@SFDC_OPP_ADLS_STAGE/opportunity/',
  FILE_FORMAT => 'SFDC_PARQUET_FF',
  IGNORE_CASE => TRUE));

-- Raw, append-only: every pull is kept (audit trail and rebuild source)
CREATE TABLE IF NOT EXISTS SFDC_OPPORTUNITY_RAW
  USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) WITHIN GROUP (ORDER BY ORDER_ID)
    FROM TABLE(INFER_SCHEMA(
      LOCATION    => '@SFDC_OPP_ADLS_STAGE/opportunity/',
      FILE_FORMAT => 'SFDC_PARQUET_FF',
      IGNORE_CASE => TRUE)))
  ENABLE_SCHEMA_EVOLUTION = TRUE;   -- new Salesforce fields get added automatically

ALTER TABLE SFDC_OPPORTUNITY_RAW ADD COLUMN IF NOT EXISTS _SRC_FILE  VARCHAR;
ALTER TABLE SFDC_OPPORTUNITY_RAW ADD COLUMN IF NOT EXISTS _LOADED_AT TIMESTAMP_LTZ;

-- Auto-ingest pipe on the shared notification integration, scoped to opportunity/ in the new stage
CREATE PIPE IF NOT EXISTS SFDC_OPPORTUNITY_PIPE
  AUTO_INGEST = TRUE
  INTEGRATION = 'SFDC_ADLS_NOTIFICATION_INT'
  COMMENT = 'Salesforce Opportunity Parquet -> DEMO.SFDC_OPPORTUNITY_RAW'
AS
COPY INTO SFDC_OPPORTUNITY_RAW
FROM @SFDC_OPP_ADLS_STAGE/opportunity/
FILE_FORMAT = (FORMAT_NAME = 'SFDC_PARQUET_FF')
PATTERN = '.*[.]parquet'            -- skip the zero-byte ADLS Gen2 directory entries
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (_SRC_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME)
ON_ERROR = 'SKIP_FILE';

-- Load the file(s) that arrived before the pipe existed (only looks back 7 days)
ALTER PIPE SFDC_OPPORTUNITY_PIPE REFRESH;

SELECT SYSTEM$PIPE_STATUS('SFDC_OPPORTUNITY_PIPE');
