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
| Azure      | Key Vault                      | `kv-jominslearning-sfdc` (secret `snowflake-sfdc-adf-svc-password`) | new |
| ADF        | Factory                        | `jominsdevadf`                         | existing |
| ADF        | Linked services                | `LS_Salesforce_Lab`, `LS_ADLS_GEN2` (existing); `LS_KEY_VAULT`, `LS_SNOWFLAKE` (new) | mixed |

Folder convention in the container: `salesforce-raw/<object>/...parquet`.

## End-to-end flow

```
Salesforce (Account) --ADF jominsdevadf--> ADLS jominsdevadls/salesforce-raw/account/*.parquet
   --Event Grid--> queue snowpipe-events --Snowpipe--> LEARNING_DB.DEMO.SFDC_ACCOUNT_RAW
```

## Orchestration (ADF `PL_SFDC_TO_ADLS_ACCOUNT`)

Trigger `TR_SFDC_ACCOUNT_WEEKDAYS_10AM_PT`: Mon-Fri 10:00 Pacific (follows PST/PDT).

```
Copy_Account_To_ADLS                  Salesforce SOQL -> salesforce-raw/account/yyyy/MM/dd/account_<ts>_<runId>.parquet
Until_Snowpipe_Loaded (<= 15 min)     every 30s: COPY_HISTORY for this run's file; Fail if Snowpipe reports a failed load
Merge_To_Target                       CALL SP_MERGE_SFDC_ACCOUNT()  (RAW stream -> SFDC_ACCOUNT)
```
Snowflake access: `LS_SNOWFLAKE` signs in as `SFDC_ADF_SVC`, using the password from Key Vault `kv-jominslearning-sfdc`.

## Run order

1. `azure/01_azure_setup.md`: container, queue, Event Grid subscription on `jominsdevadls`.
2. `salesforce/01_create_synthetic_accounts.apex`: 5 synthetic Accounts (`SNOWPIPE-TEST-001..005`).
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
