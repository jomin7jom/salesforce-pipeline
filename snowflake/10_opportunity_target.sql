-- 10_opportunity_target.sql : incremental load RAW -> reporting target (one row per Opportunity Id)
--   SFDC_OPPORTUNITY_RAW (append-only, Snowpipe)
--     -> SFDC_OPPORTUNITY_RAW_STREAM (only rows not yet processed)
--     -> CALL SP_MERGE_SFDC_OPPORTUNITY()   (no schedule here; ADF orchestrates/schedules it)
--     -> SFDC_OPPORTUNITY (reporting target, deduplicated upsert)
-- ACCOUNT_ID joins to SFDC_ACCOUNT.ID (many Opportunities -> one Account), used as the Power BI relationship.
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

-- 1. Reporting target
CREATE TABLE IF NOT EXISTS SFDC_OPPORTUNITY (
  ID                    VARCHAR(18)    NOT NULL PRIMARY KEY,   -- informational only in Snowflake
  NAME                  VARCHAR,
  ACCOUNT_ID            VARCHAR(18),                           -- informational FK to SFDC_ACCOUNT.ID
  AMOUNT                NUMBER(18,2),
  QUANTITY              NUMBER(18,2),                          -- Salesforce TotalOpportunityQuantity
  CLOSE_DATE            DATE,
  STAGE_NAME            VARCHAR,
  PROBABILITY           NUMBER(5,2),
  TYPE                  VARCHAR,
  LEAD_SOURCE           VARCHAR,
  IS_CLOSED             BOOLEAN,
  IS_WON                BOOLEAN,
  DESCRIPTION           VARCHAR,
  CREATED_AT_UTC        TIMESTAMP_NTZ,
  LAST_MODIFIED_AT_UTC  TIMESTAMP_NTZ,
  _SRC_FILE             VARCHAR,
  _LOADED_AT            TIMESTAMP_LTZ,
  _MERGED_AT            TIMESTAMP_LTZ,
  CONSTRAINT FK_SFDC_OPPORTUNITY_ACCOUNT FOREIGN KEY (ACCOUNT_ID) REFERENCES SFDC_ACCOUNT (ID)
)
COMMENT = 'Reporting: current state of each Salesforce Opportunity (incremental MERGE from SFDC_OPPORTUNITY_RAW)';

-- 2. Change tracking on RAW. SHOW_INITIAL_ROWS so the first CALL picks up rows already loaded.
CREATE STREAM IF NOT EXISTS SFDC_OPPORTUNITY_RAW_STREAM
  ON TABLE SFDC_OPPORTUNITY_RAW
  APPEND_ONLY = TRUE
  SHOW_INITIAL_ROWS = TRUE
  COMMENT = 'New rows in SFDC_OPPORTUNITY_RAW not yet merged into SFDC_OPPORTUNITY';

-- 3. Incremental MERGE procedure: dedupe the new batch, upsert only if the record is newer.
--    Reading the stream inside the MERGE advances it, so each RAW row is processed once.
CREATE OR REPLACE PROCEDURE SP_MERGE_SFDC_OPPORTUNITY()
  RETURNS VARIANT
  LANGUAGE SQL
  COMMENT = 'Incremental merge SFDC_OPPORTUNITY_RAW_STREAM -> SFDC_OPPORTUNITY. Called by ADF after the Salesforce copy.'
  EXECUTE AS OWNER
AS
$$
DECLARE
  rows_inserted INTEGER DEFAULT 0;
  rows_updated  INTEGER DEFAULT 0;
BEGIN
  MERGE INTO LEARNING_DB.DEMO.SFDC_OPPORTUNITY t
  USING (
    SELECT ID, NAME, ACCOUNTID,
           AMOUNT::NUMBER(18,2)                   AS AMOUNT,
           TOTALOPPORTUNITYQUANTITY::NUMBER(18,2) AS QUANTITY,
           TO_DATE(CLOSEDATE)                     AS CLOSE_DATE,
           STAGENAME, PROBABILITY::NUMBER(5,2)    AS PROBABILITY,
           TYPE, LEADSOURCE, ISCLOSED::BOOLEAN    AS IS_CLOSED, ISWON::BOOLEAN AS IS_WON,
           DESCRIPTION, CREATEDDATE, LASTMODIFIEDDATE, _SRC_FILE, _LOADED_AT
    FROM LEARNING_DB.DEMO.SFDC_OPPORTUNITY_RAW_STREAM
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY LASTMODIFIEDDATE DESC, _LOADED_AT DESC) = 1
  ) s
  ON t.ID = s.ID
  WHEN MATCHED AND s.LASTMODIFIEDDATE > t.LAST_MODIFIED_AT_UTC THEN UPDATE SET
    t.NAME = s.NAME, t.ACCOUNT_ID = s.ACCOUNTID, t.AMOUNT = s.AMOUNT, t.QUANTITY = s.QUANTITY,
    t.CLOSE_DATE = s.CLOSE_DATE, t.STAGE_NAME = s.STAGENAME, t.PROBABILITY = s.PROBABILITY,
    t.TYPE = s.TYPE, t.LEAD_SOURCE = s.LEADSOURCE, t.IS_CLOSED = s.IS_CLOSED, t.IS_WON = s.IS_WON,
    t.DESCRIPTION = s.DESCRIPTION, t.CREATED_AT_UTC = s.CREATEDDATE,
    t.LAST_MODIFIED_AT_UTC = s.LASTMODIFIEDDATE,
    t._SRC_FILE = s._SRC_FILE, t._LOADED_AT = s._LOADED_AT, t._MERGED_AT = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (
    ID, NAME, ACCOUNT_ID, AMOUNT, QUANTITY, CLOSE_DATE, STAGE_NAME, PROBABILITY, TYPE, LEAD_SOURCE,
    IS_CLOSED, IS_WON, DESCRIPTION, CREATED_AT_UTC, LAST_MODIFIED_AT_UTC, _SRC_FILE, _LOADED_AT, _MERGED_AT
  ) VALUES (
    s.ID, s.NAME, s.ACCOUNTID, s.AMOUNT, s.QUANTITY, s.CLOSE_DATE, s.STAGENAME, s.PROBABILITY, s.TYPE, s.LEADSOURCE,
    s.IS_CLOSED, s.IS_WON, s.DESCRIPTION, s.CREATEDDATE, s.LASTMODIFIEDDATE, s._SRC_FILE, s._LOADED_AT, CURRENT_TIMESTAMP()
  );

  SELECT "number of rows inserted", "number of rows updated"
    INTO :rows_inserted, :rows_updated
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

  RETURN OBJECT_CONSTRUCT(
    'status',        'SUCCEEDED',
    'rows_inserted', rows_inserted,
    'rows_updated',  rows_updated,
    'target_rows',   (SELECT COUNT(*) FROM LEARNING_DB.DEMO.SFDC_OPPORTUNITY),
    'merged_at',     CURRENT_TIMESTAMP());
END;
$$;

-- First load of what Snowpipe already brought in (ADF calls this on every later run)
CALL SP_MERGE_SFDC_OPPORTUNITY();
