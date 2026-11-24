# Power BI: Opportunities by Account page

Adds Salesforce Opportunities to `SFDC_Account_Revenue` and a second report page that shows
Opportunity Amount per Account for the selected City and Industry.

Prerequisite: `snowflake/10_opportunity_target.sql` and `11_opportunity_access.sql` have run, so
`SFDC_REPORT_ROLE` can read `LEARNING_DB.DEMO.SFDC_OPPORTUNITY`.

## Quick path: open the updated project
`SFDC_Account_Revenue.pbip` already contains the new table, the relationship, the measures and the page.
1. Open `SFDC_Account_Revenue.pbip` in Power BI Desktop and click **Home > Refresh**.
2. Go to the **Opportunities by Account** page and pick a City and/or Industry in the dropdowns.
3. **File > Save**, then publish as before (`01_build_revenue_report.md` step 5). The scheduled 11:00 PT refresh
   now covers the new table too. The Opportunity load runs at 10:15 PT, so it's in place by then.

If Desktop rejects a file, note the file name and message it shows. The manual steps below build the same thing.

## Model

| Table | Grain | Key |
|---|---|---|
| `SFDC_ACCOUNT` | 1 row per Account | `ID` |
| `SFDC_OPPORTUNITY` (new) | 1 row per Opportunity | `ID`, with `ACCOUNT_ID` -> `SFDC_ACCOUNT[ID]` |
| `VW_SFDC_ACCOUNT_REVENUE_SNAPSHOT` | 1 row per Account per day | unrelated, as before |

**Relationship:** `SFDC_OPPORTUNITY[ACCOUNT_ID]` (many) -> `SFDC_ACCOUNT[ID]` (one), single direction.
City and Industry filters on `SFDC_ACCOUNT` therefore flow down to Opportunities. The snapshot view stays
unrelated, so slicers on this page don't affect the line charts on the first page.

## Manual steps
1. **Home > Get data > Snowflake** (same server, warehouse, and role `SFDC_REPORT_ROLE` as before). Tick
   `LEARNING_DB > DEMO > SFDC_OPPORTUNITY` and click **Load**.
2. **Model view:** drag `SFDC_OPPORTUNITY[ACCOUNT_ID]` onto `SFDC_ACCOUNT[ID]`. Check that it's *Many to one*,
   *Single* cross-filter direction, and active. Hide `ACCOUNT_ID`.
3. Measures (on `SFDC_OPPORTUNITY`):
```dax
Opportunity Amount   = SUM ( SFDC_OPPORTUNITY[AMOUNT] )
Opportunity Count    = COUNTROWS ( SFDC_OPPORTUNITY )
Open Pipeline Amount = CALCULATE ( [Opportunity Amount], SFDC_OPPORTUNITY[IS_CLOSED] = FALSE () )
Won Amount           = CALCULATE ( [Opportunity Amount], SFDC_OPPORTUNITY[IS_WON] = TRUE () )
Total Quantity       = SUM ( SFDC_OPPORTUNITY[QUANTITY] )
```
   Format the amount measures as Currency with 0 decimals, and the count and quantity measures as whole numbers.
4. New page **Opportunities by Account**:

| Position | Visual | Fields |
|---|---|---|
| Top row | **Slicer** (Dropdown): *City* | `SFDC_ACCOUNT[BILLING_CITY]` |
| Top row | **Slicer** (Dropdown): *Industry* | `SFDC_ACCOUNT[INDUSTRY]` |
| Top row | 3 **Cards** | `[Opportunity Amount]`, `[Opportunity Count]`, `[Open Pipeline Amount]` |
| Left | **Clustered bar chart**: *Opportunity Amount by Account* | Y-axis `SFDC_ACCOUNT[NAME]`, X-axis `[Opportunity Amount]`, sorted descending |
| Right | **Table**: *Opportunities per Account* | `SFDC_ACCOUNT[NAME]`, `[BILLING_CITY]`, `[INDUSTRY]`, `[Opportunity Count]`, `[Opportunity Amount]`, `[Open Pipeline Amount]`, `[Won Amount]`, `[Total Quantity]` |

Use the Account columns (not Opportunity ones) for City, Industry and Name, so the relationship does the filtering.

## What you'll see
- **After the first run:** 20+ Opportunities (about 4 per account with 5 accounts, or 3 with 7). All are open,
  so Open Pipeline Amount equals Opportunity Amount and Won Amount is blank.
- **Over the following days:** each daily Apex run adds another 20+, advances some stages, and closes past-due
  ones as Won or Lost. Won Amount and Open Pipeline then diverge.
