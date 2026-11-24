-- 01_integrations.sql  : run as ACCOUNTADMIN (only role here with CREATE INTEGRATION)
USE ROLE ACCOUNTADMIN;

-- Storage integration: Snowflake's Azure app reads the new container
CREATE STORAGE INTEGRATION IF NOT EXISTS SFDC_ADLS_STORAGE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '33bb46cc-beeb-404b-becf-07ccf7603174'
  STORAGE_ALLOWED_LOCATIONS = ('azure://jominsdevadls.blob.core.windows.net/salesforce-raw/')
  COMMENT = 'Salesforce Parquet landing zone (ADLS Gen2)';

-- Notification integration: Snowpipe reads BlobCreated events from the storage queue
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS SFDC_ADLS_NOTIFICATION_INT
  ENABLED = TRUE
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = AZURE_STORAGE_QUEUE
  AZURE_STORAGE_QUEUE_PRIMARY_URI = 'https://jominsdevadls.queue.core.windows.net/snowpipe-events'
  AZURE_TENANT_ID = '33bb46cc-beeb-404b-becf-07ccf7603174'
  COMMENT = 'Event Grid -> storage queue for Salesforce Snowpipes';

-- Copy AZURE_CONSENT_URL + AZURE_MULTI_TENANT_APP_NAME from both, then do Azure step 6
DESC STORAGE INTEGRATION SFDC_ADLS_STORAGE_INT;
DESC NOTIFICATION INTEGRATION SFDC_ADLS_NOTIFICATION_INT;
