@IsTest
private class TestDriveCustomSlotSelectorTest {

    @TestSetup
    static void setup() {
        Account dealer = new Account(
            Name = 'Test Dealer',
            BillingPostalCode = '94043'
        );
        insert dealer;

        Product2 product = new Product2(
            Name        = 'Electra X',
            IsActive    = true
        );
        insert product;

        VehicleDefinition vehicleDef = new VehicleDefinition(
            Name      = 'Electra X',
            ProductId = product.Id
        );
        insert vehicleDef;

        Asset asset = new Asset(
            Name    = 'Electra X',
            AccountId = dealer.Id
        );
        insert asset;

        Vehicle vehicle = new Vehicle(
            Name                        = 'Electra X',
            VehicleDefinitionId         = vehicleDef.Id,
            AssetId                     = asset.Id,
            VehicleIdentificationNumber = 'TEST0000000000001'
        );
        insert vehicle;

        insert new List<TimeSlot__c>{
            new TimeSlot__c(
                Dealer__c    = dealer.Id,
                Vehicle__c   = vehicle.Id,
                Date__c      = Date.today().addDays(1),
                StartTime__c = Time.newInstance(9, 0, 0, 0),
                EndTime__c   = Time.newInstance(10, 0, 0, 0),
                Status__c    = 'Available',
                Capacity__c  = 3
            ),
            new TimeSlot__c(
                Dealer__c    = dealer.Id,
                Vehicle__c   = vehicle.Id,
                Date__c      = Date.today().addDays(1),
                StartTime__c = Time.newInstance(11, 0, 0, 0),
                EndTime__c   = Time.newInstance(12, 0, 0, 0),
                Status__c    = 'Available',
                Capacity__c  = 2
            )
        };
    }

    // ── getAvailableSlots: happy path ──────────────────────────────────────────

    @IsTest
    static void testGetAvailableSlots_Success() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip         = '94043';
        req.vehicleName = 'Electra X';
        req.reqDate     = Date.today().addDays(1);
        req.maxResults  = 10;

        Test.startTest();
        TestDriveCustomSlotSelector.GetSlotsResponse resp =
            TestDriveCustomSlotSelector.getAvailableSlots(req);
        Test.stopTest();

        System.assertEquals('Success', resp.message);
        System.assertEquals(2, resp.options.size());
        System.assert(resp.options[0].startTime <= resp.options[1].startTime, 'Slots should be sorted ascending by startTime');
    }

    @IsTest
    static void testGetAvailableSlots_MaxResultsTrimming() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip         = '94043';
        req.vehicleName = 'Electra X';
        req.reqDate     = Date.today().addDays(1);
        req.maxResults  = 1;

        Test.startTest();
        TestDriveCustomSlotSelector.GetSlotsResponse resp =
            TestDriveCustomSlotSelector.getAvailableSlots(req);
        Test.stopTest();

        System.assertEquals(1, resp.options.size());
    }

    // ── getAvailableSlots: no slots found ─────────────────────────────────────

    @IsTest
    static void testGetAvailableSlots_NoSlotsFound() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip         = '00000';
        req.vehicleName = 'Electra X';
        req.reqDate     = Date.today().addDays(1);

        Test.startTest();
        try {
            TestDriveCustomSlotSelector.getAvailableSlots(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assert(ex.getMessage().contains('No dealer territory found'));
        }
        Test.stopTest();
    }

    // ── getAvailableSlots: null request ───────────────────────────────────────

    @IsTest
    static void testGetAvailableSlots_NullRequest() {
        Test.startTest();
        try {
            TestDriveCustomSlotSelector.getAvailableSlots(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('Request is required.', ex.getMessage());
        }
        Test.stopTest();
    }

    // ── validateRequest ───────────────────────────────────────────────────────

    @IsTest
    static void testValidation_BlankZip() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip     = '   ';
        req.reqDate = Date.today().addDays(1);

        Test.startTest();
        try {
            TestDriveCustomSlotSelector.getAvailableSlots(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('ZIP is required.', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidation_NullDate() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip     = '94043';
        req.reqDate = null;

        Test.startTest();
        try {
            TestDriveCustomSlotSelector.getAvailableSlots(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('Date is required.', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidation_PastDate() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip     = '94043';
        req.reqDate = Date.today().addDays(-1);

        Test.startTest();
        try {
            TestDriveCustomSlotSelector.getAvailableSlots(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('Date must not be in the past.', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidation_DateBeyond30Days() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip     = '94043';
        req.reqDate = Date.today().addDays(31);

        Test.startTest();
        try {
            TestDriveCustomSlotSelector.getAvailableSlots(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('Date must be within the next 30 days.', ex.getMessage());
        }
        Test.stopTest();
    }

    // ── ZIP normalization ──────────────────────────────────────────────────────

    @IsTest
    static void testZipNormalization() {
        TestDriveCustomSlotSelector.SlotRequest req = new TestDriveCustomSlotSelector.SlotRequest();
        req.zip         = '9-4-0-4-3';
        req.vehicleName = 'Electra X';
        req.reqDate     = Date.today().addDays(1);

        Test.startTest();
        TestDriveCustomSlotSelector.GetSlotsResponse resp =
            TestDriveCustomSlotSelector.getAvailableSlots(req);
        Test.stopTest();

        System.assertEquals('Success', resp.message);
    }

    // ── invocableGetAvailableSlots ─────────────────────────────────────────────

    @IsTest
    static void testInvocable_Success() {
        TestDriveCustomSlotSelector.SlotsRequestWrapper w = new TestDriveCustomSlotSelector.SlotsRequestWrapper();
        w.zip        = '94043';
        w.vehicleId  = 'Electra X';
        w.reqDate    = String.valueOf(Date.today().addDays(1));
        w.maxResults = 10;

        Test.startTest();
        List<TestDriveCustomSlotSelector.SlotsResponseWrapper> results =
            TestDriveCustomSlotSelector.invocableGetAvailableSlots(
                new List<TestDriveCustomSlotSelector.SlotsRequestWrapper>{ w }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].json);
        System.assert(results[0].json.contains('Success'));
    }

    @IsTest
    static void testInvocable_EmptyPayload() {
        Test.startTest();
        List<TestDriveCustomSlotSelector.SlotsResponseWrapper> results =
            TestDriveCustomSlotSelector.invocableGetAvailableSlots(
                new List<TestDriveCustomSlotSelector.SlotsRequestWrapper>()
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].json);
    }

    @IsTest
    static void testInvocable_NullPayload() {
        Test.startTest();
        List<TestDriveCustomSlotSelector.SlotsResponseWrapper> results =
            TestDriveCustomSlotSelector.invocableGetAvailableSlots(null);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].json);
    }

    @IsTest
    static void testInvocable_InvalidDate_ReturnsErrorJson() {
        TestDriveCustomSlotSelector.SlotsRequestWrapper w = new TestDriveCustomSlotSelector.SlotsRequestWrapper();
        w.zip     = '94043';
        w.reqDate = 'not-a-date';

        Test.startTest();
        List<TestDriveCustomSlotSelector.SlotsResponseWrapper> results =
            TestDriveCustomSlotSelector.invocableGetAvailableSlots(
                new List<TestDriveCustomSlotSelector.SlotsRequestWrapper>{ w }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(
            results[0].json.contains('Failed') || results[0].json.contains('Date is required'),
            'Expected error message in JSON response'
        );
    }

}