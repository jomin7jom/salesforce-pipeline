# ADF copy pipeline: Salesforce Account -> ADLS (`salesforce-raw/account/`)

Reuses the existing factory `jominsdevadf` (rg `jominslearning`, westus) and its two
working linked services, so no secrets are needed here:

| Reused | Type | Points to |
|---|---|---|
| `LS_Salesforce_Lab` | SalesforceV2, OAuth2 client credentials, API 64.0 | `orgfarm-51c1d2abfb-dev-ed.develop.my.salesforce.com` |
| `LS_ADLS_GEN2` | AzureBlobFS (account key) | `https://jominsdevadls.dfs.core.windows.net/` |

New (definitions in `azure/adf/`):

| New | Purpose |
|---|---|
| `DS_SFDC_ACCOUNT` | Salesforce `Account` object |
| `DS_ADLS_SFDC_PARQUET` | Parquet (snappy) in `salesforce-raw`, folder and file name passed in as parameters |
| `PL_SFDC_TO_ADLS_ACCOUNT` | Copy activity: SOQL -> `account/yyyy/MM/dd/account_<ts>_<runId>.parquet` |

The existing `CopyPipeline_Test_Salesforce` and its `*_b4b` datasets (which write to
`salesforce-lab`) are left alone.

**Why the file names are unique:** Snowpipe tracks which files it has already loaded
by path. If every run overwrote a fixed name such as `account.parquet`, it would be
easy to lose or double-load data. Writing a new file per run avoids that.

## Prerequisite
The `salesforce-raw` container must exist (`azure/01_azure_setup.md` step 2).

## Step 1: Create 7 synthetic Accounts in Salesforce
1. Log in to the dev org, then open the Setup gear > **Developer Console**.
2. Go to **Debug > Open Execute Anonymous Window**, paste
   `salesforce/01_create_synthetic_accounts.apex`, and click **Execute**.
3. Check the results in the **Query Editor** tab:
   `SELECT Id, Name, Industry FROM Account WHERE Name LIKE 'SNOWPIPE-TEST-%'` should return 5 rows.

The script is safe to run again, because it skips names that already exist. The pipeline's
default SOQL only selects these `SNOWPIPE-TEST-%` records. Override the `soqlQuery`
parameter to pull all Accounts later.

## Step 2: Deploy the datasets and pipeline
```powershell
$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$f   = "https://management.azure.com/subscriptions/104de54b-16c7-4ae0-b509-73182439e483/resourceGroups/jominslearning/providers/Microsoft.DataFactory/factories/jominsdevadf"
$dir = (Resolve-Path ".\azure\adf").Path   # run from the repo root

# Datasets first, because the pipeline references them
& $az rest --method put --url "$f/datasets/DS_SFDC_ACCOUNT?api-version=2018-06-01"         --body "@$dir\DS_SFDC_ACCOUNT.json"
& $az rest --method put --url "$f/datasets/DS_ADLS_SFDC_PARQUET?api-version=2018-06-01"    --body "@$dir\DS_ADLS_SFDC_PARQUET.json"
& $az rest --method put --url "$f/pipelines/PL_SFDC_TO_ADLS_ACCOUNT?api-version=2018-06-01" --body "@$dir\PL_SFDC_TO_ADLS_ACCOUNT.json"
```
This writes straight to the live factory. If you use ADF Studio, click **Refresh** to see the new objects.
(If the factory is Git-connected, author there instead.)

## Step 3: Run it and check the result
```powershell
$runId = & $az rest --method post --url "$f/pipelines/PL_SFDC_TO_ADLS_ACCOUNT/createRun?api-version=2018-06-01" --query runId -o tsv
"runId=$runId"

# Repeat until status is Succeeded or Failed (a 5-row copy usually takes 30-90 seconds)
& $az rest --method get --url "$f/pipelineruns/$($runId)?api-version=2018-06-01" --query "[status, message, durationInMs]" -o tsv
```
To see rows read and written, open ADF Studio > **Monitor** > the run > the Copy activity's
details. It should show **5 rows read / 5 rows written**.

Then confirm the file landed:
```powershell
& $az storage fs file list --account-name jominsdevadls -f salesforce-raw --path account --recursive `
  --auth-mode key --query "[].[name, contentLength, lastModified]" -o tsv
```
(`--auth-mode key` is needed because your Owner role doesn't include data-plane read access.)

## Notes
- Salesforce `datetime` fields arrive in Parquet as timestamps. `USE_LOGICAL_TYPE = TRUE`
  on `SFDC_PARQUET_FF` makes Snowflake read them as TIMESTAMP rather than raw numbers.
- After the first run, check `snowflake/04_validate.sql` (COPY_HISTORY) to confirm
  that Event Grid actually fired for files ADF writes to ADLS Gen2. If the file is in ADLS
  but Snowflake never saw it, check that the Event Grid subscription's delivered-events
  metric went up.
