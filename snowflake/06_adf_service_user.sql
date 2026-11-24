-- 06_adf_service_user.sql : least-privilege Snowflake identity for ADF
-- The password is NOT stored here. It is generated, saved to Key Vault
-- (kv-jominslearning-sfdc / snowflake-sfdc-adf-svc-password) and passed in at run time:
--   snow sql -c dev_snowflake -f snowflake/06_adf_service_user.sql -D svc_password=<from Key Vault>
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS SFDC_ADF_ROLE
  COMMENT = 'ADF orchestration: call SP_MERGE_SFDC_ACCOUNT and check Snowpipe COPY_HISTORY';
GRANT ROLE SFDC_ADF_ROLE TO ROLE SYSADMIN;   -- keep role hierarchy intact

GRANT USAGE  ON WAREHOUSE SNOWFLAKE_LEARNING_WH                    TO ROLE SFDC_ADF_ROLE;
GRANT USAGE  ON DATABASE  LEARNING_DB                              TO ROLE SFDC_ADF_ROLE;
GRANT USAGE  ON SCHEMA    LEARNING_DB.DEMO                         TO ROLE SFDC_ADF_ROLE;
GRANT USAGE  ON PROCEDURE LEARNING_DB.DEMO.SP_MERGE_SFDC_ACCOUNT() TO ROLE SFDC_ADF_ROLE;
GRANT SELECT ON TABLE     LEARNING_DB.DEMO.SFDC_ACCOUNT_RAW        TO ROLE SFDC_ADF_ROLE;  -- for COPY_HISTORY

-- LEGACY_SERVICE = non-interactive user that can sign in with a password (no MFA).
-- (TYPE = SERVICE does not allow passwords; switch to key-pair if LEGACY_SERVICE is retired.)
CREATE USER IF NOT EXISTS SFDC_ADF_SVC
  TYPE                 = LEGACY_SERVICE
  PASSWORD             = '<% svc_password %>'
  MUST_CHANGE_PASSWORD = FALSE
  DEFAULT_ROLE         = SFDC_ADF_ROLE
  DEFAULT_WAREHOUSE    = SNOWFLAKE_LEARNING_WH
  DEFAULT_NAMESPACE    = LEARNING_DB.DEMO
  COMMENT              = 'ADF service user; password in Key Vault kv-jominslearning-sfdc';

GRANT ROLE SFDC_ADF_ROLE TO USER SFDC_ADF_SVC;
