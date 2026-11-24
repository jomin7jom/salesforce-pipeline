-- 12_validate_opportunity.sql : read-only checks for the Opportunity pipeline
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE SCHEMA LEARNING_DB.DEMO;

SELECT SYSTEM$PIPE_STATUS('SFDC_OPPORTUNITY_PIPE');   -- executionState should be RUNNING

SELECT file_name, status, row_count, row_parsed, first_error_message, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'SFDC_OPPORTUNITY_RAW',
  START_TIME => DATEADD(hour, -24, CURRENT_TIMESTAMP())))
ORDER BY last_load_time DESC;

-- Raw keeps every pull; target has one row per Opportunity
SELECT 'raw' AS layer, COUNT(*) AS rows, COUNT(DISTINCT ID) AS ids FROM SFDC_OPPORTUNITY_RAW
UNION ALL
SELECT 'target', COUNT(*), COUNT(DISTINCT ID) FROM SFDC_OPPORTUNITY;

-- Every Opportunity should match an Account (0 = relationship is clean for Power BI)
SELECT COUNT(*) AS orphan_opportunities
FROM SFDC_OPPORTUNITY o
LEFT JOIN SFDC_ACCOUNT a ON a.ID = o.ACCOUNT_ID
WHERE a.ID IS NULL;

-- What the Power BI page will show
SELECT a.NAME AS account, a.BILLING_CITY, a.INDUSTRY,
       COUNT(o.ID)                                   AS opportunities,
       SUM(o.AMOUNT)                                 AS opportunity_amount,
       SUM(IFF(o.IS_CLOSED, 0, o.AMOUNT))            AS open_pipeline,
       SUM(IFF(o.IS_WON, o.AMOUNT, 0))               AS won_amount
FROM SFDC_ACCOUNT a
LEFT JOIN SFDC_OPPORTUNITY o ON o.ACCOUNT_ID = a.ID
GROUP BY 1, 2, 3
ORDER BY opportunity_amount DESC NULLS LAST;
