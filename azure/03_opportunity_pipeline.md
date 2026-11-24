# Opportunity pipeline: Salesforce Opportunity -> ADLS (`salesforce-opportunity-raw/opportunity/`)

Second object on the same pattern as Account, in its own container. Everything here is new; the
Account container, its Event Grid subscription, pipeline and trigger are not changed.

| Reused | Notes |
|---|---|
| Storage account `jominsdevadls` | |
| Queue `snowpipe-events` | One queue serves both pipes. Snowflake routes each event to the pipe whose stage matches the file path |
| Event Grid system topic on the account | A storage account can only have one |
| Notification integration `SFDC_ADLS_NOTIFICATION_INT` | Already reads `snowpipe-events` |
| ADF `jominsdevadf`, `LS_Salesforce_Lab`, `LS_ADLS_GEN2`, `LS_SNOWFLAKE` | |

| New | Purpose |
|---|---|
| Container `salesforce-opportunity-raw` | Opportunity Parquet files |
| Event Grid subscription `snowpipe-sfdc-opp-blob-created` | BlobCreated in the new container -> `snowpipe-events` |
| `DS_SFDC_OPPORTUNITY` | Salesforce `Opportunity` object |
| `DS_ADLS_SFDC_OPPORTUNITY_PARQUET` | Parquet (snappy) in `salesforce-opportunity-raw` |
| `PL_SFDC_TO_ADLS_OPPORTUNITY` | Copy -> wait for Snowpipe -> `CALL SP_MERGE_SFDC_OPPORTUNITY()` |
| `TR_SFDC_OPPORTUNITY_WEEKDAYS_1015AM_PT` | Mon–Fri 10:15 Pacific, after the 6:45 Account run |

## Run order (whole Opportunity build)

1. `salesforce/02_create_daily_opportunities.apex`: today's 20+ Opportunities.
2. This file, steps 1–3: container, event subscription, role on the new container.
3. `snowflake/08_opportunity_integration_and_stage.sql`: storage integration and stage, then `LIST`.
4. This file, step 4: deploy the ADF objects and run the pipeline once. The first file lands, and the
   run **fails at the Snowpipe wait**, because the table and pipe don't exist yet. That's expected.
5. `snowflake/09_opportunity_table_and_pipe.sql`: infer the table from that file, create the pipe, `REFRESH`.
6. `snowflake/10_opportunity_target.sql`: target table, stream, merge procedure.
7. `snowflake/11_opportunity_access.sql`: grants for ADF and Power BI.
8. Run the pipeline again (step 4's `createRun`). This time it should succeed end to end.
9. This file, step 5: start the trigger.
10. `snowflake/12_validate_opportunity.sql`, then refresh Power BI (`powerbi/02_opportunities_page.md`).

## Setup

```powershell
$SA    = "jominsdevadls"
$CONT  = "salesforce-opportunity-raw"
$QUEUE = "snowpipe-events"
$SUB   = "snowpipe-sfdc-opp-blob-created"

$SA_JSON = az storage account list --query "[?name=='$SA'] | [0]" -o json | ConvertFrom-Json
$RG    = $SA_JSON.resourceGroup
$SA_ID = $SA_JSON.id
```

### 1. Container (management plane: your Owner role has no data-plane rights)
```powershell
az storage container-rm create --storage-account $SA -g $RG -n $CONT --public-access off
```

### 2. Event Grid subscription on the existing system topic -> existing queue
```powershell
$TOPIC = az eventgrid system-topic list -g $RG --query "[?source=='$SA_ID'].name | [0]" -o tsv
"TOPIC=$TOPIC"   # must not be empty: the Account setup created or found it

az eventgrid system-topic event-subscription create -g $RG `
  --system-topic-name $TOPIC -n $SUB `
  --endpoint-type storagequeue `
  --endpoint "$SA_ID/queueServices/default/queues/$QUEUE" `
  --included-event-types Microsoft.Storage.BlobCreated `
  --subject-begins-with "/blobServices/default/containers/$CONT/" `
  --subject-ends-with ".parquet"
```

### 3. Let Snowflake's app read the new container
The app already has *Storage Queue Data Contributor* on `snowpipe-events`, so only the container needs a role.
Use the same `$APP_SP` as step 5 of `01_azure_setup.md`. First run `DESC STORAGE INTEGRATION SFDC_OPP_ADLS_STORAGE_INT`
(from `08_…sql`) and confirm `AZURE_MULTI_TENANT_APP_NAME` has the same prefix as the Account integration. If it
doesn't, open its `AZURE_CONSENT_URL`, click **Accept**, and use that app's service principal instead.
```powershell
az role assignment create --assignee-object-id $APP_SP --assignee-principal-type ServicePrincipal `
  --role "Storage Blob Data Reader" `
  --scope "$SA_ID/blobServices/default/containers/$CONT"
```

### 4. Deploy the ADF objects and run once
```powershell
$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$sub = az account show --query id -o tsv
$f   = "https://management.azure.com/subscriptions/$sub/resourceGroups/jominslearning/providers/Microsoft.DataFactory/factories/jominsdevadf"
$dir = (Resolve-Path ".\azure\adf").Path   # run from the repo root

& $az rest --method put --url "$f/datasets/DS_SFDC_OPPORTUNITY?api-version=2018-06-01"              --body "@$dir\DS_SFDC_OPPORTUNITY.json"
& $az rest --method put --url "$f/datasets/DS_ADLS_SFDC_OPPORTUNITY_PARQUET?api-version=2018-06-01" --body "@$dir\DS_ADLS_SFDC_OPPORTUNITY_PARQUET.json"
& $az rest --method put --url "$f/pipelines/PL_SFDC_TO_ADLS_OPPORTUNITY?api-version=2018-06-01"     --body "@$dir\PL_SFDC_TO_ADLS_OPPORTUNITY.json"
& $az rest --method put --url "$f/triggers/TR_SFDC_OPPORTUNITY_WEEKDAYS_1015AM_PT?api-version=2018-06-01" --body "@$dir\TR_SFDC_OPPORTUNITY_WEEKDAYS_1015AM_PT.json"

$runId = & $az rest --method post --url "$f/pipelines/PL_SFDC_TO_ADLS_OPPORTUNITY/createRun?api-version=2018-06-01" --query runId -o tsv
& $az rest --method get --url "$f/pipelineruns/$($runId)?api-version=2018-06-01" --query "[status, message, durationInMs]" -o tsv
```
Confirm the file landed:
```powershell
az storage fs file list --account-name $SA -f $CONT --path opportunity --recursive `
  --auth-mode key --query "[].[name, contentLength, lastModified]" -o tsv
```

### 5. Start the schedule (only after a clean end-to-end run)
A trigger is created in the *Stopped* state.
```powershell
& $az rest --method post --url "$f/triggers/TR_SFDC_OPPORTUNITY_WEEKDAYS_1015AM_PT/start?api-version=2018-06-01"
```

## Daily routine
Run `salesforce/02_create_daily_opportunities.apex` **before 10:15 PT** on weekdays. Records created
later are picked up by the next weekday's run. Every run pulls all `SNOWPIPE-TEST-OPP-%` records (a full
snapshot), and the Snowflake merge only applies rows whose `LastModifiedDate` is newer.

Deleted Opportunities are not handled: a record deleted in Salesforce stays in `SFDC_OPPORTUNITY`.
