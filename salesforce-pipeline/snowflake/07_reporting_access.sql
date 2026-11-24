-- 07_reporting_access.sql : Power BI support (snapshot history view + read-only report user)
-- Password is NOT stored here: generated, saved to Key Vault
-- (kv-jominslearning-sfdc / snowflake-sfdc-report-svc-password) and passed in with -D report_password=...
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

-- Revenue history: AnnualRevenue of every account as of each snapshot date (= Pacific date of a load).
-- Built from SFDC_ACCOUNT_RAW, which keeps every pull. An account missing from a day's pull
-- (e.g. after switching to incremental SOQL) carries its last known value forward.
CREATE OR REPLACE VIEW VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT
  COMMENT = 'Power BI: AnnualRevenue per account per snapshot date (Pacific), carried forward between changes'
AS
WITH daily AS (
  SELECT ID, NAME, INDUSTRY, BILLINGCITY, BILLINGCOUNTRY, ANNUALREVENUE,
         TO_DATE(CONVERT_TIMEZONE('America/Los_Angeles', _LOADED_AT)) AS SNAPSHOT_DATE
  FROM SFDC_ACCOUNT_RAW
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ID, TO_DATE(CONVERT_TIMEZONE('America/Los_Angeles', _LOADED_AT))
    ORDER BY LASTMODIFIEDDATE DESC, _LOADED_AT DESC) = 1
),
snapshot_dates AS (
  SELECT DISTINCT SNAPSHOT_DATE FROM daily
)
SELECT
  d.SNAPSHOT_DATE,
  a.ID,
  a.NAME,
  a.INDUSTRY,
  a.BILLINGCITY    AS BILLING_CITY,
  a.BILLINGCOUNTRY AS BILLING_COUNTRY,
  a.ANNUALREVENUE::NUMBER(18,2) AS ANNUAL_REVENUE
FROM snapshot_dates d
JOIN daily a
  ON a.SNAPSHOT_DATE <= d.SNAPSHOT_DATE
QUALIFY ROW_NUMBER() OVER (PARTITION BY d.SNAPSHOT_DATE, a.ID ORDER BY a.SNAPSHOT_DATE DESC) = 1;

-- Read-only role for Power BI
CREATE ROLE IF NOT EXISTS SFDC_REPORT_ROLE
  COMMENT = 'Power BI: read-only on Salesforce reporting objects';
GRANT ROLE SFDC_REPORT_ROLE TO ROLE SYSADMIN;

GRANT USAGE  ON WAREHOUSE SNOWFLAKE_LEARNING_WH                           TO ROLE SFDC_REPORT_ROLE;
GRANT USAGE  ON DATABASE  LEARNING_DB                                     TO ROLE SFDC_REPORT_ROLE;
GRANT USAGE  ON SCHEMA    LEARNING_DB.DEMO                                TO ROLE SFDC_REPORT_ROLE;
GRANT SELECT ON TABLE     LEARNING_DB.DEMO.SFDC_ACCOUNT                   TO ROLE SFDC_REPORT_ROLE;
GRANT SELECT ON VIEW      LEARNING_DB.DEMO.VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT TO ROLE SFDC_REPORT_ROLE;
-- No grant on SFDC_ACCOUNT_RAW: the view reads it with its owner's rights.

CREATE USER IF NOT EXISTS SFDC_REPORT_SVC
  TYPE                 = LEGACY_SERVICE
  PASSWORD             = '<% report_password %>'
  MUST_CHANGE_PASSWORD = FALSE
  DEFAULT_ROLE         = SFDC_REPORT_ROLE
  DEFAULT_WAREHOUSE    = SNOWFLAKE_LEARNING_WH
  DEFAULT_NAMESPACE    = LEARNING_DB.DEMO
  COMMENT              = 'Power BI service user; password in Key Vault kv-jominslearning-sfdc';

GRANT ROLE SFDC_REPORT_ROLE TO USER SFDC_REPORT_SVC;
