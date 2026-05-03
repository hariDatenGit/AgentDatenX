@IsTest
private class FindDealershipByZipTest {

    @TestSetup
    static void setup() {
        Account dealer = new Account(
            Name = 'Electra Dealer West',
            Phone = '+1-650-555-0100',
            BillingStreet = '100 Main St',
            BillingCity = 'Mountain View',
            BillingState = 'CA',
            BillingPostalCode = '94043'
        );
        insert dealer;

        ZipToDealer__c mapping = new ZipToDealer__c(
            Zip__c = '94043',
            Dealer__c = dealer.Id,
            DistanceKm__c = 4.2,
            Priority__c = 1,
            Active__c = true,
            VehicleModel__c = 'Electra X'
        );
        insert mapping;
    }

    @IsTest
    static void testMatchFound() {
        FindDealershipByZip.DealerRequest req = new FindDealershipByZip.DealerRequest();
        req.zip = '94043';
        req.model = 'Electra X';

        List<FindDealershipByZip.DealerResult> results =
            FindDealershipByZip.findDealership(new List<FindDealershipByZip.DealerRequest>{ req });

        System.assertEquals(1, results.size());
        System.assertEquals('Electra Dealer West', results[0].dealerName);
        System.assertEquals(4.2, results[0].distanceKm);
        System.assertNotEquals(null, results[0].dealerId);
    }

    @IsTest
    static void testNoMatchFound() {
        FindDealershipByZip.DealerRequest req = new FindDealershipByZip.DealerRequest();
        req.zip = '00000';
        req.model = 'Electra X';

        List<FindDealershipByZip.DealerResult> results =
            FindDealershipByZip.findDealership(new List<FindDealershipByZip.DealerRequest>{ req });

        System.assertEquals(null, results[0].dealerId);
        System.assertEquals('No dealership found for this ZIP and model', results[0].dealerName);
    }

    @IsTest
    static void testInactiveRecordExcluded() {
        Account dealer = [SELECT Id FROM Account LIMIT 1];
        ZipToDealer__c inactive = new ZipToDealer__c(
            Zip__c = '99999',
            Dealer__c = dealer.Id,
            DistanceKm__c = 1.0,
            Priority__c = 1,
            Active__c = false,
            VehicleModel__c = 'Electra X'
        );
        insert inactive;

        FindDealershipByZip.DealerRequest req = new FindDealershipByZip.DealerRequest();
        req.zip = '99999';
        req.model = 'Electra X';

        List<FindDealershipByZip.DealerResult> results =
            FindDealershipByZip.findDealership(new List<FindDealershipByZip.DealerRequest>{ req });

        System.assertEquals(null, results[0].dealerId);
    }
}