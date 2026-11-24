// Creates 5 synthetic Account records for the Snowpipe pipeline test.
// Run in Salesforce: Setup gear > Developer Console > Debug > Open Execute Anonymous Window
// Safe to re-run: skips names that already exist.
String prefix = 'SNOWPIPE-TEST-';
// 006 shares a city with 001 (Seattle); 007 shares an industry with 001 (Technology).
String[] industries = new String[]{ 'Technology', 'Finance', 'Healthcare', 'Retail', 'Manufacturing', 'Finance', 'Technology' };
String[] cities     = new String[]{ 'Seattle', 'Austin', 'Boston', 'Denver', 'Chicago', 'Seattle', 'Atlanta' };
String[] states     = new String[]{ 'WA', 'TX', 'MA', 'CO', 'IL', 'WA', 'GA' };
// This org has State/Country picklists enabled: set the ISO *Code* fields, not the text fields.

Set<String> existing = new Set<String>();
for (Account a : [SELECT Name FROM Account WHERE Name LIKE 'SNOWPIPE-TEST-%']) {
    existing.add(a.Name);
}

List<Account> toInsert = new List<Account>();
for (Integer i = 1; i <= industries.size(); i++) {
    String name = prefix + String.valueOf(i).leftPad(3, '0');
    if (existing.contains(name)) continue;
    toInsert.add(new Account(
        Name              = name,
        Industry          = industries[i - 1],
        Type              = 'Prospect',
        AnnualRevenue     = 250000 * i,
        NumberOfEmployees = 25 * i,
        BillingCity       = cities[i - 1],
        BillingStateCode   = states[i - 1],
        BillingCountryCode = 'US',
        Description       = 'Synthetic record for Salesforce -> ADLS -> Snowpipe test'
    ));
}
// The org's standard Account duplicate rule fuzzy-matches 'SNOWPIPE-TEST-006' against 001..005.
// It's an "allow with alert" rule, which Apex must opt past explicitly (a "block" rule would still block).
Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.allowSave = true;
dml.OptAllOrNone = true;   // any other error still fails the whole insert
Database.insert(toInsert, dml);
System.debug('Inserted ' + toInsert.size() + ' synthetic accounts; ' + existing.size() + ' already existed.');
