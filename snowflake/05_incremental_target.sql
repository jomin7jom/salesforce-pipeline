-- 05_incremental_target.sql : incremental load RAW -> reporting target (one row per Account Id)
--   SFDC_ACCOUNT_RAW (append-only, Snowpipe)
--     -> SFDC_ACCOUNT_RAW_STREAM (only rows not yet processed)
--     -> CALL SP_MERGE_SFDC_ACCOUNT()   (no schedule here; ADF orchestrates/schedules it)
--     -> SFDC_ACCOUNT (reporting target, deduplicated upsert)
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

-- 1. Reporting target
CREATE TABLE IF NOT EXISTS SFDC_ACCOUNT (
  ID                    VARCHAR(18)    NOT NULL PRIMARY KEY,   -- informational only in Snowflake
  NAME                  VARCHAR,
  INDUSTRY              VARCHAR,
  TYPE                  VARCHAR,
  ANNUAL_REVENUE        NUMBER(18,2),
  NUMBER_OF_EMPLOYEES   NUMBER(38,0),
  BILLING_CITY          VARCHAR,
  BILLING_COUNTRY       VARCHAR,
  DESCRIPTION           VARCHAR,
  CREATED_AT_UTC        TIMESTAMP_NTZ,
  LAST_MODIFIED_AT_UTC  TIMESTAMP_NTZ,
  _SRC_FILE             VARCHAR,
  _LOADED_AT            TIMESTAMP_LTZ,
  _MERGED_AT            TIMESTAMP_LTZ
)
COMMENT = 'Reporting: current state of each Salesforce Account (incremental MERGE from SFDC_ACCOUNT_RAW)';

-- 2. Change tracking on RAW. SHOW_INITIAL_ROWS so the first CALL picks up rows already loaded.
CREATE STREAM IF NOT EXISTS SFDC_ACCOUNT_RAW_STREAM
  ON TABLE SFDC_ACCOUNT_RAW
  APPEND_ONLY = TRUE
  SHOW_INITIAL_ROWS = TRUE
  COMMENT = 'New rows in SFDC_ACCOUNT_RAW not yet merged into SFDC_ACCOUNT';

-- 3. Incremental MERGE procedure: dedupe the new batch, upsert only if the record is newer,
--    and delete target rows that Salesforce reports as deleted. ADF pulls deleted records with
--    includeDeletedObjects = true (they come from the Salesforce recycle bin, kept about 15 days).
--    Reading the stream inside the MERGE advances it, so each RAW row is processed once.
CREATE OR REPLACE PROCEDURE SP_MERGE_SFDC_ACCOUNT()
  COPY GRANTS                                   -- keep SFDC_ADF_ROLE's USAGE when replaced
  RETURNS VARIANT
  LANGUAGE SQL
  COMMENT = 'Incremental merge SFDC_ACCOUNT_RAW_STREAM -> SFDC_ACCOUNT. Called by ADF after the Salesforce copy.'
  EXECUTE AS OWNER
AS
$$
DECLARE
  rows_inserted INTEGER DEFAULT 0;
  rows_updated  INTEGER DEFAULT 0;
  rows_deleted  INTEGER DEFAULT 0;
BEGIN
  MERGE INTO LEARNING_DB.DEMO.SFDC_ACCOUNT t
  USING (
    SELECT ID, NAME, INDUSTRY, TYPE, ANNUALREVENUE, NUMBEROFEMPLOYEES,
           BILLINGCITY, BILLINGCOUNTRY, DESCRIPTION, CREATEDDATE, LASTMODIFIEDDATE,
           COALESCE(ISDELETED, FALSE) AS IS_DELETED,   -- NULL in rows loaded before deletes were pulled
           _SRC_FILE, _LOADED_AT
    FROM LEARNING_DB.DEMO.SFDC_ACCOUNT_RAW_STREAM
    -- A deleted record can keep the same LastModifiedDate, so the latest load breaks the tie
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY LASTMODIFIEDDATE DESC, _LOADED_AT DESC) = 1
  ) s
  ON t.ID = s.ID
  WHEN MATCHED AND s.IS_DELETED THEN DELETE                           -- deleted in Salesforce
  WHEN MATCHED AND s.LASTMODIFIEDDATE > t.LAST_MODIFIED_AT_UTC THEN UPDATE SET
    t.NAME = s.NAME, t.INDUSTRY = s.INDUSTRY, t.TYPE = s.TYPE,
    t.ANNUAL_REVENUE = s.ANNUALREVENUE, t.NUMBER_OF_EMPLOYEES = s.NUMBEROFEMPLOYEES,
    t.BILLING_CITY = s.BILLINGCITY, t.BILLING_COUNTRY = s.BILLINGCOUNTRY,
    t.DESCRIPTION = s.DESCRIPTION, t.CREATED_AT_UTC = s.CREATEDDATE,
    t.LAST_MODIFIED_AT_UTC = s.LASTMODIFIEDDATE,
    t._SRC_FILE = s._SRC_FILE, t._LOADED_AT = s._LOADED_AT, t._MERGED_AT = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED AND NOT s.IS_DELETED THEN INSERT (                 -- never insert a deleted record
    ID, NAME, INDUSTRY, TYPE, ANNUAL_REVENUE, NUMBER_OF_EMPLOYEES, BILLING_CITY, BILLING_COUNTRY,
    DESCRIPTION, CREATED_AT_UTC, LAST_MODIFIED_AT_UTC, _SRC_FILE, _LOADED_AT, _MERGED_AT
  ) VALUES (
    s.ID, s.NAME, s.INDUSTRY, s.TYPE, s.ANNUALREVENUE, s.NUMBEROFEMPLOYEES, s.BILLINGCITY, s.BILLINGCOUNTRY,
    s.DESCRIPTION, s.CREATEDDATE, s.LASTMODIFIEDDATE, s._SRC_FILE, s._LOADED_AT, CURRENT_TIMESTAMP()
  );

  SELECT "number of rows inserted", "number of rows updated", "number of rows deleted"
    INTO :rows_inserted, :rows_updated, :rows_deleted
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

  RETURN OBJECT_CONSTRUCT(
    'status',        'SUCCEEDED',
    'rows_inserted', rows_inserted,
    'rows_updated',  rows_updated,
    'rows_deleted',  rows_deleted,
    'target_rows',   (SELECT COUNT(*) FROM LEARNING_DB.DEMO.SFDC_ACCOUNT),
    'merged_at',     CURRENT_TIMESTAMP());
END;
$$;
