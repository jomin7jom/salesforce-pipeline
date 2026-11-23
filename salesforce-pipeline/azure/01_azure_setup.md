# Azure setup (existing storage account `jominsdevadls`)

Reuses the storage account. The container, queue and Event Grid subscription are new.
The existing `snowflake-lab` container is not touched.

Tenant ID that Snowflake will use: `33bb46cc-beeb-404b-becf-07ccf7603174`
(taken from your existing integration; confirm it's the tenant that holds `jominsdevadls`).

The commands use the Azure CLI (`winget install Microsoft.AzureCLI`, then `az login`).
Every step can also be done in the Azure Portal.

```powershell
$SA     = "jominsdevadls"
$CONT   = "salesforce-raw"
$QUEUE  = "snowpipe-events"
$SUB    = "snowpipe-sfdc-blob-created"

# Look up the account's resource group, region and ID
$SA_JSON = az storage account list --query "[?name=='$SA'] | [0]" -o json | ConvertFrom-Json
$RG    = $SA_JSON.resourceGroup
$LOC   = $SA_JSON.primaryLocation
$SA_ID = $SA_JSON.id
"RG=$RG  LOC=$LOC  HNS=$($SA_JSON.isHnsEnabled)"
```

## 1. Register the Event Grid provider (once per subscription)
```powershell
az provider register --namespace Microsoft.EventGrid
az provider show --namespace Microsoft.EventGrid --query registrationState
```

## 2. New container
Uses the management plane (ARM). Your subscription **Owner** role doesn't include
blob/queue *data* permissions, so `--auth-mode login` data-plane commands would fail.
```powershell
az storage container-rm create --storage-account $SA -g $RG -n $CONT --public-access off
```

## 3. New storage queue (receives the BlobCreated events)
```powershell
az rest --method put `
  --url "https://management.azure.com$SA_ID/queueServices/default/queues/$($QUEUE)?api-version=2023-05-01" `
  --body '{}'
```
Queue URI for Snowflake: `https://jominsdevadls.queue.core.windows.net/snowpipe-events`

## 4. Event Grid: send BlobCreated events in `salesforce-raw` to the queue
A storage account can have only **one** Event Grid system topic, so reuse it if one exists:
```powershell
$TOPIC = az eventgrid system-topic list -g $RG --query "[?source=='$SA_ID'].name | [0]" -o tsv
if (-not $TOPIC) {
  $TOPIC = "$SA-topic"
  az eventgrid system-topic create -g $RG -n $TOPIC -l $LOC `
    --topic-type Microsoft.Storage.StorageAccounts --source $SA_ID
}

az eventgrid system-topic event-subscription create -g $RG `
  --system-topic-name $TOPIC -n $SUB `
  --endpoint-type storagequeue `
  --endpoint "$SA_ID/queueServices/default/queues/$QUEUE" `
  --included-event-types Microsoft.Storage.BlobCreated `
  --subject-begins-with "/blobServices/default/containers/$CONT/" `
  --subject-ends-with ".parquet"
```
The subject filter keeps events from `snowflake-lab` and every other container out of this queue.

## 5. Run AFTER `snowflake/01_integrations.sql`: consent and RBAC
1. Run `DESC` on both new integrations and compare `AZURE_MULTI_TENANT_APP_NAME`
   with the existing one (`wjjbizsnowflakepacint_1794852861899`). If they match, the app
   has already been consented in your tenant. If either is new, open its `AZURE_CONSENT_URL`
   and click **Accept**.
2. Assign the roles on the **new** container and queue only. Existing grants on
   `snowflake-lab` don't cover these.
```powershell
# Existing Snowflake service principal "wjjbizsnowflakepacint" (appId 60cd383e-...).
# Only reuse it if DESC INTEGRATION shows the same app name prefix.
$APP_SP = "d4fc177b-ec6c-4e04-b0c9-7fa7d411927f"

# Read files (use "Storage Blob Data Contributor" if you want PURGE / REMOVE)
az role assignment create --assignee-object-id $APP_SP --assignee-principal-type ServicePrincipal `
  --role "Storage Blob Data Reader" `
  --scope "$SA_ID/blobServices/default/containers/$CONT"

# Read and delete queue messages
az role assignment create --assignee-object-id $APP_SP --assignee-principal-type ServicePrincipal `
  --role "Storage Queue Data Contributor" `
  --scope "$SA_ID/queueServices/default/queues/$QUEUE"
```
Checked 2026-11-23: the Snowflake app has Storage Blob Data Reader **only** on
`snowflake-lab`, so both assignments above are needed. Role assignments can take
a few minutes to take effect.
