# Power BI: Salesforce Account Revenue report

## Quick path: open the generated project
`powerbi/SFDC_Account_Revenue.pbip` already has the model, the measures, and all 4 visuals described below.
1. Double-click `SFDC_Account_Revenue.pbip`, or in Power BI Desktop go to **File > Open > Browse** and pick it.
   If Desktop asks to enable **Power BI Project / TMDL / PBIR**, go to **File > Options > Preview features**,
   tick them, and restart Desktop.
2. The model has no data yet, so click **Home > Refresh**. When prompted for Snowflake credentials, use
   **Snowflake** auth with user `SFDC_REPORT_SVC` and the Key Vault password (step 1 below).
3. **File > Save** keeps it as PBIP (text files). **File > Save as > .pbix** produces a single file to publish.

If Desktop rejects a file, note the file name and message it shows. The manual steps below
build the same report from scratch.

Four visuals: revenue **per City** and **per Industry**, each as a bar chart (current) and a
line chart (growth over time).

| Source (Snowflake `LEARNING_DB.DEMO`) | Grain | Used for |
|---|---|---|
| `SFDC_ACCOUNT` | 1 row per Account (current state) | Bar charts |
| `VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT` | 1 row per Account per snapshot date | Line charts (growth) |

"Revenue" here is the Salesforce **Account.AnnualRevenue** field, the account's stated annual
revenue. It is not bookings or opportunity amounts. A snapshot date is the Pacific date a
pipeline run loaded the data (weekdays after the 6:45 PT Account run).

## 1. Get the password
Azure portal > **Key vaults** > `kv-jominslearning-sfdc` > **Objects > Secrets** >
`snowflake-sfdc-report-svc-password` > current version > **Show Secret Value**.

## 2. Connect (Power BI Desktop)
1. Go to **Home > Get data > More… > Snowflake** and click **Connect**.
2. Fill in:
   - **Server:** `NRZVPQQ-FV30704.snowflakecomputing.com`
   - **Warehouse:** `SNOWFLAKE_LEARNING_WH`
   - **Advanced options > Role name:** `SFDC_REPORT_ROLE`
   - **Data connectivity mode:** **Import**
3. Credentials: open the **Snowflake** tab and enter user `SFDC_REPORT_SVC` and the password from step 1.
4. In the Navigator, open `LEARNING_DB` > `DEMO`, tick **`SFDC_ACCOUNT`** and
   **`VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT`**, then click **Load**.

The two tables stay unrelated in the model. Delete any relationship Power BI auto-creates
between them in **Model view**.

## 3. Measures
Select the `VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT` table, then go to **Home > New measure**. Add each measure below,
then set its format in **Measure tools**.

```dax
Total Revenue =
SUM ( SFDC_ACCOUNT[ANNUAL_REVENUE] )
```
Format: Currency, 0 decimals.

```dax
Snapshot Revenue =
SUM ( VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT[ANNUAL_REVENUE] )
```
Format: Currency, 0 decimals.

```dax
Previous Snapshot Revenue =
VAR CurrentDate = MAX ( VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT[SNAPSHOT_DATE] )
VAR PrevDate =
    CALCULATE (
        MAX ( VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT[SNAPSHOT_DATE] ),
        VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT[SNAPSHOT_DATE] < CurrentDate
    )
RETURN
    IF (
        NOT ISBLANK ( PrevDate ),
        CALCULATE (
            [Snapshot Revenue],
            VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT[SNAPSHOT_DATE] = PrevDate
        )
    )
```
Format: Currency, 0 decimals.

```dax
Revenue Growth % =
DIVIDE ( [Snapshot Revenue] - [Previous Snapshot Revenue], [Previous Snapshot Revenue] )
```
Format: Percentage, 1 decimal.

City and Industry filters from a visual still apply inside these measures. Only the date
filter is swapped, so each line shows growth for its own City or Industry.

## 4. Visuals (2 x 2 layout)
Name the page **Account Revenue**.

| Position | Visual | Fields |
|---|---|---|
| Top-left | **Clustered bar chart**: *Revenue by City* | Y-axis `SFDC_ACCOUNT[BILLING_CITY]`, X-axis `[Total Revenue]`. Sort by Total Revenue, descending |
| Top-right | **Clustered bar chart**: *Revenue by Industry* | Y-axis `SFDC_ACCOUNT[INDUSTRY]`, X-axis `[Total Revenue]`. Sort by Total Revenue, descending |
| Bottom-left | **Line chart**: *Revenue growth by City* | X-axis `VW…[SNAPSHOT_DATE]`, Y-axis `[Snapshot Revenue]`, Legend `VW…[BILLING_CITY]`, Tooltips `[Revenue Growth %]` |
| Bottom-right | **Line chart**: *Revenue growth by Industry* | X-axis `VW…[SNAPSHOT_DATE]`, Y-axis `[Snapshot Revenue]`, Legend `VW…[INDUSTRY]`, Tooltips `[Revenue Growth %]` |

Settings for the line charts:
- On the X-axis field, choose **SNAPSHOT_DATE** (not *Date Hierarchy*) from the field's dropdown.
  Then go to **Format > X-axis > Type: Continuous**.
- Turn on **Format > Markers**, so days with a single snapshot still show as dots.
- Optionally turn on **Format > Data labels** on the bar charts.

Optional: add a slicer on `BILLING_COUNTRY`. Because the tables are unrelated, a slicer filters
only the visuals built from its own table. Add one slicer per table, or ask for a shared City and Industry
dimension to be added in Snowflake.

## 5. Publish and scheduled refresh (Power BI service)
1. In Power BI Desktop, go to **File > Save as** and save `SFDC_Account_Revenue.pbix`, then **Home > Publish**.
2. In the service, open the semantic model's **Settings > Data source credentials > Edit**.
   Choose authentication **Basic**, user `SFDC_REPORT_SVC`, and the password from Key Vault.
   No gateway is needed, because Snowflake is a cloud source.
3. Under **Scheduled refresh**, turn it on, choose time zone **(UTC-08:00) Pacific Time**, refresh
   **Weekly** on Mon–Fri at **11:00 AM**. That's after the 6:45 Account and 10:15 Opportunity ADF runs, which usually finish in under 5 minutes.

## What you'll see now vs later
- **Today:** the bar charts show 5 cities and 5 industries, one account each, totalling $3.75M.
  The line charts show **a single point per series** (snapshot 2026-11-23), and growth % is blank.
- **After more weekday runs:** each run adds a snapshot date. Lines move only when AnnualRevenue
  changes in Salesforce or new accounts appear.
- **To demo growth now:** in Salesforce, edit AnnualRevenue on a few `SNOWPIPE-TEST-*`
  accounts, run `PL_SFDC_TO_ADLS_ACCOUNT` manually on a *different day* than the last run, and refresh.
  Snapshots are per Pacific date, so two runs on the same day count as one snapshot.
