# Salesforce Parquet -> Snowflake (Snowpipe auto-ingest from ADLS Gen2)

Reuses the existing Snowflake database, schema and warehouse, and the existing
storage account `jominsdevadls`. The container, queue, Event Grid subscription,
integrations, file format, stage, table and pipe are all new.
Nothing reuses the `snowflake-lab` container, `LAB_AZURE_STORAGE_INT` or `ERP_REVENUE_ADLS_STAGE`.

## Names used

| Layer      | Object                         | Name                                   | New? |
|------------|--------------------------------|----------------------------------------|------|
| Azure      | Storage account (ADLS Gen2)    | `jominsdevadls`                        | existing |
| Azure      | Container                      | `salesforce-raw`                       | new  |
| Azure      | Storage queue                  | `snowpipe-events`                      | new  |
| Azure      | Event Grid system topic        | existing one on the account, else `jominsdevadls-topic` | check |
| Azure      | Event Grid subscription        | `snowpipe-sfdc-blob-created`           | new  |
| Snowflake  | Role                           | `ACCOUNTADMIN`                         | existing |
| Snowflake  | Warehouse                      | `SNOWFLAKE_LEARNING_WH`                | existing |
| Snowflake  | Database / schema              | `LEARNING_DB.DEMO`                     | existing |
| Snowflake  | Storage integration            | `SFDC_ADLS_STORAGE_INT`                | new  |
| Snowflake  | Notification integration       | `SFDC_ADLS_NOTIFICATION_INT`           | new  |
| Snowflake  | File format                    | `SFDC_PARQUET_FF`                      | new  |
| Snowflake  | Stage                          | `SFDC_ADLS_STAGE`                      | new  |
| Snowflake  | Table / pipe (per SF object)   | `SFDC_ACCOUNT_RAW` / `SFDC_ACCOUNT_PIPE` | new |
| Snowflake  | Reporting target / stream / proc | `SFDC_ACCOUNT` / `SFDC_ACCOUNT_RAW_STREAM` / `SP_MERGE_SFDC_ACCOUNT()` | new |
| Snowflake  | ADF service user / role        | `SFDC_ADF_SVC` (LEGACY_SERVICE, password) / `SFDC_ADF_ROLE` | new |
| Snowflake  | Power BI view / user / role    | `VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT` / `SFDC_REPORT_SVC` / `SFDC_REPORT_ROLE` (read-only) | new |
| Power BI   | Report project (PBIP)          | `powerbi/SFDC_Account_Revenue.pbip` (+ `.SemanticModel/`, `.Report/`) | new |
| Power BI   | Open / build guide             | `powerbi/01_build_revenue_report.md`   | new |
| Azure      | Key Vault                      | `kv-jominslearning-sfdc` (secret `snowflake-sfdc-adf-svc-password`) | new |
| ADF        | Factory                        | `jominsdevadf`                         | existing |
| ADF        | Linked services                | `LS_Salesforce_Lab`, `LS_ADLS_GEN2` (existing); `LS_KEY_VAULT`, `LS_SNOWFLAKE` (new) | mixed |

Folder convention in the container: `salesforce-raw/<object>/...parquet`.

### Opportunity (second object, own container)

| Layer      | Object                         | Name                                   | New? |
|------------|--------------------------------|----------------------------------------|------|
| Salesforce | Daily test data                | `salesforce/02_create_daily_opportunities.apex` (`SNOWPIPE-TEST-OPP-*`, 20+ per run) | new |
| Azure      | Container                      | `salesforce-opportunity-raw`           | new  |
| Azure      | Event Grid subscription        | `snowpipe-sfdc-opp-blob-created` (into the same `snowpipe-events` queue) | new |
| ADF        | Datasets / pipeline / trigger  | `DS_SFDC_OPPORTUNITY`, `DS_ADLS_SFDC_OPPORTUNITY_PARQUET` / `PL_SFDC_TO_ADLS_OPPORTUNITY` / `TR_SFDC_OPPORTUNITY_WEEKDAYS_1015AM_PT` | new |
| Snowflake  | Storage integration / stage    | `SFDC_OPP_ADLS_STORAGE_INT` / `SFDC_OPP_ADLS_STAGE` (notification integration shared) | new |
| Snowflake  | Raw table / pipe               | `SFDC_OPPORTUNITY_RAW` / `SFDC_OPPORTUNITY_PIPE` | new |
| Snowflake  | Reporting target / stream / proc | `SFDC_OPPORTUNITY` / `SFDC_OPPORTUNITY_RAW_STREAM` / `SP_MERGE_SFDC_OPPORTUNITY()` | new |
| Power BI   | Table, relationship, page      | `SFDC_OPPORTUNITY[ACCOUNT_ID]` -> `SFDC_ACCOUNT[ID]`; page *Opportunities by Account* (`powerbi/02_opportunities_page.md`) | new |

Build order: `azure/03_opportunity_pipeline.md`. Snowflake scripts `08`–`12`.

## End-to-end flow

```
Salesforce (Account) --ADF jominsdevadf--> ADLS jominsdevadls/salesforce-raw/account/*.parquet
   --Event Grid--> queue snowpipe-events --Snowpipe--> LEARNING_DB.DEMO.SFDC_ACCOUNT_RAW
```

## Orchestration (ADF `PL_SFDC_TO_ADLS_ACCOUNT`)

Trigger `TR_SFDC_ACCOUNT_WEEKDAYS_6 45AM_PT` (the name contains a space): Mon-Fri 6:45 Pacific (follows PST/PDT).

```
Copy_Account_To_ADLS                  Salesforce SOQL -> salesforce-raw/account/yyyy/MM/dd/account_<ts>_<runId>.parquet
Until_Snowpipe_Loaded (<= 15 min)     every 30s: COPY_HISTORY for this run's file; Fail if Snowpipe reports a failed load
Merge_To_Target                       CALL SP_MERGE_SFDC_ACCOUNT()  (RAW stream -> SFDC_ACCOUNT)
```
Snowflake access: `LS_SNOWFLAKE` signs in as `SFDC_ADF_SVC`, using the password from Key Vault `kv-jominslearning-sfdc`.

### Deleted records
Both pipelines pull with `includeDeletedObjects = true` and select `IsDeleted`, so records in the Salesforce
recycle bin arrive flagged as deleted. The merge procedures then delete those rows from `SFDC_ACCOUNT` and
`SFDC_OPPORTUNITY`, and never insert one. Deleting an Account in Salesforce also deletes its Opportunities,
so both tables stay in step. The revenue history view only shows accounts still in `SFDC_ACCOUNT`.

Limit: the recycle bin keeps records for about 15 days. A record that is hard-deleted or purged before the
next run is never reported and has to be removed by hand. Upgrade steps and checks: `snowflake/13_handle_deletes.sql`.

## Run order

1. `azure/01_azure_setup.md`: container, queue, Event Grid subscription on `jominsdevadls`.
2. `salesforce/01_create_synthetic_accounts.apex`: 7 synthetic Accounts (`SNOWPIPE-TEST-001..007`).
3. `azure/02_adf_salesforce_to_adls.md`: deploy and run `PL_SFDC_TO_ADLS_ACCOUNT`. The first
   Parquet file lands in `salesforce-raw/account/`.
4. `snowflake/01_integrations.sql`: storage and notification integrations.
5. Back in Azure: consent and RBAC for the Snowflake app (step 5 of `01_azure_setup.md`).
6. `snowflake/02_objects.sql`: file format and stage, then `LIST` shows the ADF file.
7. `snowflake/03_table_and_pipe.sql`: infer the table from that file, create the pipe, and
   `REFRESH` to load the file that was already there.
8. Run the ADF pipeline again. This tests the auto-ingest path end to end (new file -> event -> pipe).
9. `snowflake/04_validate.sql`: pipe status, COPY_HISTORY, and row counts.

Run a script with: `snow sql -c dev_snowflake -f snowflake/01_integrations.sql`

## Repository checks

Every pull request into `main` runs `.github/workflows/validate.yml`, which runs
`scripts/validate_repo.py`. It checks three things:
- JSON / Power BI project files parse;
- no Power BI cache, local settings or key files are committed;
- no hard-coded passwords or keys are present.

To run it locally before pushing, from the repo root: `python scripts/validate_repo.py`

## Daily operations

The pipeline runs Mon–Fri at 6:45 Pacific (Account) and 10:15 Pacific (Opportunity). Power BI refreshes at 11:00 Pacific.
To add new test Opportunities, run `salesforce/02_create_daily_opportunities.apex` before 10:15 PT.

| To… | Go to |
|---|---|
| See today's pipeline run | ADF Studio (`jominsdevadf`) > **Monitor > Pipeline runs** > `PL_SFDC_TO_ADLS_ACCOUNT`. `Check_Snowpipe_Load` and `Merge_To_Target` outputs show rows loaded and merged |
| See trigger firings | ADF Studio > **Monitor > Trigger runs** > `TR_SFDC_ACCOUNT_WEEKDAYS_6 45AM_PT` |
| See the "file arrived" events | Azure portal > `jominsdevadls` > **Events** > `snowpipe-sfdc-blob-created` > **Metrics** |
| See Snowpipe loads | Snowsight > Catalog > Database Explorer > `LEARNING_DB.DEMO.SFDC_ACCOUNT_RAW` > **Copy History**, or run `snowflake/04_validate.sql` |
| See Power BI refreshes | app.powerbi.com > My workspace > `SFDC_Account_Revenue` (semantic model) > **Settings > Refresh history** |
| Rerun now | ADF Studio > Author > `PL_SFDC_TO_ADLS_ACCOUNT` > **Add trigger > Trigger now** |
| Pause the schedule | ADF Studio > **Manage > Triggers** > `TR_SFDC_ACCOUNT_WEEKDAYS_6 45AM_PT` > **Stop** |
| Rotate a Snowflake password | Add a new version of the Key Vault secret, then `ALTER USER SFDC_ADF_SVC` (or `SFDC_REPORT_SVC`) `SET PASSWORD = '…'`. ADF reads the new version automatically; update the Power BI data source credentials by hand |

If a run fails at `Fail_Snowpipe_Load`, its error message includes Snowpipe's first error. Fix the
file or the table, then rerun. Snowpipe skips files it has already loaded, so a rerun only adds new data.
