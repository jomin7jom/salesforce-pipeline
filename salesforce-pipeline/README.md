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

Folder convention in the container: `salesforce-raw/<object>/...parquet`.

## End-to-end flow

```
Salesforce (Account) --ADF jominsdevadf--> ADLS jominsdevadls/salesforce-raw/account/*.parquet
   --Event Grid--> queue snowpipe-events --Snowpipe--> LEARNING_DB.DEMO.SFDC_ACCOUNT_RAW
```

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
