// Creates 5 synthetic Account records for the Snowpipe pipeline test.
// Run in Salesforce: Setup gear > Developer Console > Debug > Open Execute Anonymous Window
// Safe to re-run: skips names that already exist.
String prefix = 'SNOWPIPE-TEST-';
String[] industries = new String[]{ 'Technology', 'Finance', 'Healthcare', 'Retail', 'Manufacturing' };
String[] cities     = new String[]{ 'Seattle', 'Austin', 'Boston', 'Denver', 'Chicago' };
String[] states     = new String[]{ 'WA', 'TX', 'MA', 'CO', 'IL' };
// This org has State/Country picklists enabled: set the ISO *Code* fields, not the text fields.

Set<String> existing = new Set<String>();
for (Account a : [SELECT Name FROM Account WHERE Name LIKE 'SNOWPIPE-TEST-%']) {
    existing.add(a.Name);
}

List<Account> toInsert = new List<Account>();
for (Integer i = 1; i <= 5; i++) {
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
insert toInsert;
System.debug('Inserted ' + toInsert.size() + ' synthetic accounts; ' + existing.size() + ' already existed.');
