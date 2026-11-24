-- 08_opportunity_integration_and_stage.sql : run as ACCOUNTADMIN (only role here with CREATE INTEGRATION)
-- New storage integration for the new container. SFDC_ADLS_STORAGE_INT (Account) is not altered.
-- Snowpipe events reuse SFDC_ADLS_NOTIFICATION_INT / queue snowpipe-events (one queue, many pipes).
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

CREATE STORAGE INTEGRATION IF NOT EXISTS SFDC_OPP_ADLS_STORAGE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '33bb46cc-beeb-404b-becf-07ccf7603174'
  STORAGE_ALLOWED_LOCATIONS = ('azure://jominsdevadls.blob.core.windows.net/salesforce-opportunity-raw/')
  COMMENT = 'Salesforce Opportunity Parquet landing zone (ADLS Gen2)';

-- Compare AZURE_MULTI_TENANT_APP_NAME with SFDC_ADLS_STORAGE_INT before azure/03 step 3
DESC STORAGE INTEGRATION SFDC_OPP_ADLS_STORAGE_INT;

-- Same file format as Account (USE_LOGICAL_TYPE = TRUE keeps dates and timestamps typed)
CREATE STAGE IF NOT EXISTS SFDC_OPP_ADLS_STAGE
  URL = 'azure://jominsdevadls.blob.core.windows.net/salesforce-opportunity-raw/'
  STORAGE_INTEGRATION = SFDC_OPP_ADLS_STORAGE_INT
  FILE_FORMAT = SFDC_PARQUET_FF
  COMMENT = 'ADLS Gen2 landing container for Salesforce Opportunity Parquet';

-- Smoke test, after the role assignment in azure/03 step 3 (may take a few minutes to apply).
-- No auth error = OK. Empty until ADF writes the first file.
LIST @SFDC_OPP_ADLS_STAGE;
