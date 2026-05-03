public with sharing class FindDealershipByZip {

    @InvocableMethod(
        label='Find Dealership By ZIP'
        description='Returns the best matching dealership for a given ZIP code and vehicle model'
    )
    public static List<DealerResult> findDealership(List<DealerRequest> requests) {
        DealerRequest req = requests[0];

        List<ZipToDealer__c> matches = [
            SELECT Dealer__c, Dealer__r.Name, Dealer__r.BillingStreet,
                   Dealer__r.BillingCity, Dealer__r.BillingState,
                   Dealer__r.BillingPostalCode, Dealer__r.Phone,
                   DistanceKm__c
            FROM ZipToDealer__c
            WHERE Zip__c = :req.zip
              AND Active__c = true
              AND (VehicleModel__c = :req.model OR VehicleModel__c = null)
            ORDER BY DistanceKm__c ASC, Priority__c ASC
            LIMIT 1
        ];

        DealerResult result = new DealerResult();
        if (!matches.isEmpty()) {
            ZipToDealer__c match = matches[0];
            result.dealerId   = match.Dealer__c;
            result.dealerName = match.Dealer__r.Name;
            result.distanceKm = match.DistanceKm__c;
            result.phone      = match.Dealer__r.Phone;
            result.address    = match.Dealer__r.BillingStreet + ', '
                              + match.Dealer__r.BillingCity + ', '
                              + match.Dealer__r.BillingState + ' '
                              + match.Dealer__r.BillingPostalCode;
        } else {
            result.dealerId   = null;
            result.dealerName = 'No dealership found for this ZIP and model';
        }
        return new List<DealerResult>{ result };
    }

    public class DealerRequest {
        @InvocableVariable(required=true description='5-digit ZIP code of the customer')
        public String zip;

        @InvocableVariable(required=true description='Vehicle model the customer is interested in, e.g. Electra X')
        public String model;
    }

    public class DealerResult {
        @InvocableVariable(description='Salesforce Account ID of the matched dealership')
        public String dealerId;

        @InvocableVariable(description='Name of the dealership')
        public String dealerName;

        @InvocableVariable(description='Distance in kilometers from the ZIP code to the dealership')
        public Decimal distanceKm;

        @InvocableVariable(description='Full street address of the dealership')
        public String address;

        @InvocableVariable(description='Phone number of the dealership')
        public String phone;
    }
}