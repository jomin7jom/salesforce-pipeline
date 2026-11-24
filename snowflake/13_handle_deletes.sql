-- 13_handle_deletes.sql : one-off upgrade so records deleted in Salesforce are removed from the
-- reporting tables. Run in this order:
--   1. This file, section 1 (adds ISDELETED to both raw tables).
--   2. Section 3 of 05_incremental_target.sql and 10_opportunity_target.sql (the updated merge procedures;
--      COPY GRANTS keeps SFDC_ADF_ROLE's USAGE).
--   3. Redeploy PL_SFDC_TO_ADLS_ACCOUNT and PL_SFDC_TO_ADLS_OPPORTUNITY (they now pull IsDeleted with
--      includeDeletedObjects = true), then run both pipelines once.
--   4. This file, section 2 (checks).
--
-- Limit: Salesforce keeps deleted records in the recycle bin for about 15 days. A record that is hard-deleted
-- or purged before the next pipeline run is never reported as deleted and would need manual clean-up.
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

-- 1. Raw tables: explicit column, so the merge can reference it before the first file with IsDeleted lands
--    (schema evolution would add it too, but only once such a file is loaded).
ALTER TABLE SFDC_ACCOUNT_RAW     ADD COLUMN IF NOT EXISTS ISDELETED BOOLEAN;
ALTER TABLE SFDC_OPPORTUNITY_RAW ADD COLUMN IF NOT EXISTS ISDELETED BOOLEAN;

-- 2. Checks, after both pipelines have run with the new SOQL.
--    Each count should be 0: no target row whose latest raw version says deleted.
SELECT 'accounts still present but deleted in Salesforce' AS check_name, COUNT(*) AS problems
FROM SFDC_ACCOUNT t
JOIN (SELECT ID, ISDELETED FROM SFDC_ACCOUNT_RAW
      QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY LASTMODIFIEDDATE DESC, _LOADED_AT DESC) = 1) r
  ON r.ID = t.ID
WHERE r.ISDELETED
UNION ALL
SELECT 'opportunities still present but deleted in Salesforce', COUNT(*)
FROM SFDC_OPPORTUNITY t
JOIN (SELECT ID, ISDELETED FROM SFDC_OPPORTUNITY_RAW
      QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY LASTMODIFIEDDATE DESC, _LOADED_AT DESC) = 1) r
  ON r.ID = t.ID
WHERE r.ISDELETED;

-- How many deleted records the latest pulls reported (informational)
SELECT 'Account' AS object, COUNT_IF(ISDELETED) AS deleted_in_latest_pull, COUNT(*) AS rows_in_latest_pull
FROM SFDC_ACCOUNT_RAW
WHERE _SRC_FILE = (SELECT MAX_BY(_SRC_FILE, _LOADED_AT) FROM SFDC_ACCOUNT_RAW)
UNION ALL
SELECT 'Opportunity', COUNT_IF(ISDELETED), COUNT(*)
FROM SFDC_OPPORTUNITY_RAW
WHERE _SRC_FILE = (SELECT MAX_BY(_SRC_FILE, _LOADED_AT) FROM SFDC_OPPORTUNITY_RAW);
