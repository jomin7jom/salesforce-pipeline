// Daily synthetic Opportunities for the SNOWPIPE-TEST-* accounts (Salesforce -> ADF -> Snowflake test data).
// Run once per day in Salesforce: Setup gear > Developer Console > Debug > Open Execute Anonymous Window.
// Run it BEFORE 10:15 Pacific so that day's ADF run (TR_SFDC_OPPORTUNITY_WEEKDAYS_1015AM_PT) picks it up.
//
// Each run does two things:
//   1. Inserts at least 20 new Opportunities, spread evenly across every SNOWPIPE-TEST-% account
//      (5 accounts -> 4 each, 7 accounts -> 3 each). Each one has an Amount, a Quantity and a Close Date.
//   2. Moves older test Opportunities along: open ones may advance one stage, and open ones whose
//      Close Date has passed are closed as Won (about 60%) or Lost. This produces updates as well as inserts,
//      which exercises the incremental MERGE in Snowflake.
//
// Safe to re-run on the same day: if today's batch already exists, step 1 is skipped.
// Names look like SNOWPIPE-TEST-OPP-003-20261124-02  (account suffix - run date - sequence).

final Integer MIN_PER_RUN = 20;
final String  OPP_PREFIX  = 'SNOWPIPE-TEST-OPP-';

String[] openStages = new String[]{
    'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition',
    'Id. Decision Makers', 'Perception Analysis', 'Proposal/Price Quote', 'Negotiation/Review'
};
String[] types       = new String[]{ 'New Customer', 'Existing Customer - Upgrade', 'Existing Customer - Replacement' };
String[] leadSources = new String[]{ 'Web', 'Phone Inquiry', 'Partner Referral', 'Purchased List', 'Other' };

// Random whole number from 0 to n-1
Integer rnd(Integer n) { return Math.floor(Math.random() * n).intValue(); }

Date   today    = Date.today();
String runTag   = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0)).format('yyyyMMdd');

List<Account> accounts = [
    SELECT Id, Name FROM Account WHERE Name LIKE 'SNOWPIPE-TEST-%' ORDER BY Name
];
if (accounts.isEmpty()) {
    throw new IllegalArgumentException('No SNOWPIPE-TEST-% accounts found. Run salesforce/01_create_synthetic_accounts.apex first.');
}

// ---- 1. Today's new Opportunities -------------------------------------------------------------
String todayPattern = OPP_PREFIX + '%-' + runTag + '-%';
String allPattern   = OPP_PREFIX + '%';
Integer alreadyToday = [SELECT COUNT() FROM Opportunity WHERE Name LIKE :todayPattern];
List<Opportunity> toInsert = new List<Opportunity>();

if (alreadyToday == 0) {
    Integer perAccount = (MIN_PER_RUN + accounts.size() - 1) / accounts.size();   // round up
    for (Account a : accounts) {
        String acctSuffix = a.Name.substringAfterLast('-');          // '003'
        for (Integer n = 1; n <= perAccount; n++) {
            // Amount: $5,000 - $150,000 in steps of $500. Quantity: 1 - 50 units. Close: 7 - 90 days out.
            Decimal amount   = 5000 + 500 * rnd(291);
            Integer quantity = 1 + rnd(50);
            Integer daysOut  = 7 + rnd(84);
            toInsert.add(new Opportunity(
                Name                     = OPP_PREFIX + acctSuffix + '-' + runTag + '-' + String.valueOf(n).leftPad(2, '0'),
                AccountId                = a.Id,
                Amount                   = amount,
                TotalOpportunityQuantity = quantity,
                CloseDate                = today.addDays(daysOut),
                StageName                = openStages[rnd(3)],   // start early in the funnel
                Type                     = types[rnd(types.size())],
                LeadSource               = leadSources[rnd(leadSources.size())],
                Description              = 'Synthetic record for Salesforce -> ADLS -> Snowpipe test (batch ' + runTag + ')'
            ));
        }
    }
    insert toInsert;   // Probability is filled in by Salesforce from the stage
}

// ---- 2. Move existing test Opportunities along ---------------------------------------------------
List<Opportunity> toUpdate = new List<Opportunity>();
Integer advanced = 0, won = 0, lost = 0;
for (Opportunity o : [
        SELECT Id, StageName, CloseDate
        FROM Opportunity
        WHERE Name LIKE :allPattern AND IsClosed = FALSE AND CreatedDate < TODAY
        LIMIT 500]) {
    if (o.CloseDate < today) {
        if (Math.random() < 0.6) { o.StageName = 'Closed Won';  won++;  }
        else                     { o.StageName = 'Closed Lost'; lost++; }
        toUpdate.add(o);
    } else if (Math.random() < 0.35) {
        Integer i = openStages.indexOf(o.StageName);
        if (i >= 0 && i < openStages.size() - 1) {
            o.StageName = openStages[i + 1];
            advanced++;
            toUpdate.add(o);
        }
    }
}
update toUpdate;

System.debug('Run ' + runTag + ': inserted ' + toInsert.size()
    + (alreadyToday > 0 ? ' (skipped, ' + alreadyToday + ' already created today)' : '')
    + ' across ' + accounts.size() + ' accounts; advanced ' + advanced
    + ', closed won ' + won + ', closed lost ' + lost + '.');
