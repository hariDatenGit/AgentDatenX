@IsTest
private class TestDriveServiceTest {

    @TestSetup
    static void setup() {
        Account dealer = new Account(
            Name             = 'Test Dealer',
            BillingPostalCode = '94043'
        );
        insert dealer;

        Product2 product = new Product2(Name = 'Electra X', IsActive = true);
        insert product;

        VehicleDefinition vehicleDef = new VehicleDefinition(
            Name      = 'Electra X',
            ProductId = product.Id
        );
        insert vehicleDef;

        Asset asset = new Asset(Name = 'Electra X', AccountId = dealer.Id);
        insert asset;

        Vehicle vehicle = new Vehicle(
            Name                        = 'Electra X',
            VehicleDefinitionId         = vehicleDef.Id,
            AssetId                     = asset.Id,
            VehicleIdentificationNumber = 'TEST0000000000001'
        );
        insert vehicle;

        TimeSlot__c slot = new TimeSlot__c(
            Dealer__c    = dealer.Id,
            Vehicle__c   = vehicle.Id,
            Date__c      = Date.today().addDays(1),
            StartTime__c = Time.newInstance(9, 0, 0, 0),
            EndTime__c   = Time.newInstance(10, 0, 0, 0),
            Status__c    = 'Available',
            Capacity__c  = 3
        );
        insert slot;

        Contact con = new Contact(
            FirstName = 'Jane',
            LastName  = 'Doe',
            Email     = 'jane.doe@example.com'
        );
        insert con;

        Lead lead = new Lead(
            FirstName = 'John',
            LastName  = 'Smith',
            Company   = 'Test Co',
            Email     = 'john.smith@example.com',
            Status    = 'Open - Not Contacted'
        );
        insert lead;
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private static TestDriveService.BookRequestDTO baseRequest() {
        TimeSlot__c slot = [SELECT Id FROM TimeSlot__c LIMIT 1];
        Account dealer   = [SELECT Id FROM Account LIMIT 1];
        Vehicle vehicle  = [SELECT Id FROM Vehicle LIMIT 1];

        TestDriveService.BookRequestDTO req = new TestDriveService.BookRequestDTO();
        req.zip            = '94043';
        req.selectedSlotId = slot.Id;
        req.dealerId       = dealer.Id;
        req.vehicleId      = vehicle.Id;
        req.slotStart      = Datetime.now().addDays(1);
        req.slotEnd        = Datetime.now().addDays(1).addHours(1);
        req.channel        = 'Chat';
        return req;
    }

    // ── bookTestDrive: creates new Lead when no Contact/Lead exists ───────────

    @IsTest
    static void testBookTestDrive_CreatesNewLead() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.firstName = 'New';
        req.lastName  = 'Customer';
        req.email     = 'new.customer@example.com';

        Test.startTest();
        TestDriveService.BookResponseDTO resp = TestDriveService.bookTestDrive(req);
        Test.stopTest();

        System.assertEquals('Booked', resp.message);
        System.assertNotEquals(null, resp.testDriveId);

        Test_Drive__c td = [SELECT Lead__c, Contact__c FROM Test_Drive__c WHERE Id = :resp.testDriveId];
        System.assertNotEquals(null, td.Lead__c, 'A new Lead should be linked');
        System.assertEquals(null, td.Contact__c);
    }

    // ── bookTestDrive: links existing Contact ─────────────────────────────────

    @IsTest
    static void testBookTestDrive_LinksExistingContact() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.email = 'jane.doe@example.com';

        Test.startTest();
        TestDriveService.BookResponseDTO resp = TestDriveService.bookTestDrive(req);
        Test.stopTest();

        System.assertEquals('Booked', resp.message);
        Test_Drive__c td = [SELECT Contact__c FROM Test_Drive__c WHERE Id = :resp.testDriveId];
        System.assertNotEquals(null, td.Contact__c, 'Existing Contact should be linked');
    }

    // ── bookTestDrive: links existing Lead when no Contact found ──────────────

    @IsTest
    static void testBookTestDrive_LinksExistingLead() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.email = 'john.smith@example.com';

        Test.startTest();
        TestDriveService.BookResponseDTO resp = TestDriveService.bookTestDrive(req);
        Test.stopTest();

        System.assertEquals('Booked', resp.message);
        Test_Drive__c td = [SELECT Lead__c FROM Test_Drive__c WHERE Id = :resp.testDriveId];
        System.assertNotEquals(null, td.Lead__c, 'Existing Lead should be linked');
    }

    // ── bookTestDrive: no email — creates Lead with fallback lastName ─────────

    @IsTest
    static void testBookTestDrive_NoEmail_FallbackLastName() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.email     = null;
        req.firstName = 'Walk';
        req.lastName  = null;

        Test.startTest();
        TestDriveService.BookResponseDTO resp = TestDriveService.bookTestDrive(req);
        Test.stopTest();

        System.assertEquals('Booked', resp.message);
        Lead l = [SELECT LastName FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals('Test Drive', l.LastName);
    }

    // ── bookTestDrive: default channel is Chat when blank ─────────────────────

    @IsTest
    static void testBookTestDrive_DefaultChannel() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.channel = null;
        req.email   = 'new2@example.com';

        Test.startTest();
        TestDriveService.BookResponseDTO resp = TestDriveService.bookTestDrive(req);
        Test.stopTest();

        Test_Drive__c td = [SELECT Channel__c FROM Test_Drive__c WHERE Id = :resp.testDriveId];
        System.assertEquals('Chat', td.Channel__c);
    }

    // ── bookTestDrive: dealerName populated in response ───────────────────────

    @IsTest
    static void testBookTestDrive_DealerNameInResponse() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.email = 'dealer.test@example.com';

        Test.startTest();
        TestDriveService.BookResponseDTO resp = TestDriveService.bookTestDrive(req);
        Test.stopTest();

        System.assertEquals('Test Dealer', resp.dealerName);
    }

    // ── bookTestDrive: null request throws exception ──────────────────────────

    @IsTest
    static void testBookTestDrive_NullRequest() {
        Test.startTest();
        try {
            TestDriveService.bookTestDrive(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('Request is required.', ex.getMessage());
        }
        Test.stopTest();
    }

    // ── bookTestDrive: blank ZIP throws exception ─────────────────────────────

    @IsTest
    static void testBookTestDrive_BlankZip() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.zip = '';

        Test.startTest();
        try {
            TestDriveService.bookTestDrive(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('ZIP is required.', ex.getMessage());
        }
        Test.stopTest();
    }

    // ── bookTestDrive: null slot throws exception ─────────────────────────────

    @IsTest
    static void testBookTestDrive_NullSlot() {
        TestDriveService.BookRequestDTO req = baseRequest();
        req.selectedSlotId = null;

        Test.startTest();
        try {
            TestDriveService.bookTestDrive(req);
            System.assert(false, 'Expected exception not thrown');
        } catch (TestDriveServiceException ex) {
            System.assertEquals('Slot should be selected.', ex.getMessage());
        }
        Test.stopTest();
    }

    // ── invocableBookTestDrive: happy path with valid slotId ──────────────────

    @IsTest
    static void testInvocable_Success() {
        TimeSlot__c slot = [SELECT Id FROM TimeSlot__c LIMIT 1];

        TestDriveService.BookRequestWrapper w = new TestDriveService.BookRequestWrapper();
        w.zip            = '94043';
        w.selectedSlotId = slot.Id;
        w.firstName      = 'Invocable';
        w.lastName       = 'User';
        w.email          = 'invocable.user@example.com';
        w.slotStart      = String.valueOf(Datetime.now().addDays(1));
        w.slotEnd        = String.valueOf(Datetime.now().addDays(1).addHours(1));
        w.vehicleId      = 'placeholder';

        Test.startTest();
        List<TestDriveService.BookResponseWrapper> results =
            TestDriveService.invocableBookTestDrive(
                new List<TestDriveService.BookRequestWrapper>{ w }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].json);
        System.assert(results[0].json.contains('Booked'));
    }

    // ── invocableBookTestDrive: empty payload ─────────────────────────────────

    @IsTest
    static void testInvocable_EmptyPayload() {
        Test.startTest();
        List<TestDriveService.BookResponseWrapper> results =
            TestDriveService.invocableBookTestDrive(
                new List<TestDriveService.BookRequestWrapper>()
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].json);
    }

    // ── invocableBookTestDrive: null payload ──────────────────────────────────

    @IsTest
    static void testInvocable_NullPayload() {
        Test.startTest();
        List<TestDriveService.BookResponseWrapper> results =
            TestDriveService.invocableBookTestDrive(null);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].json);
    }

    // ── invocableBookTestDrive: invalid slotId returns error JSON ─────────────

    @IsTest
    static void testInvocable_InvalidSlotId_ReturnsErrorJson() {
        TestDriveService.BookRequestWrapper w = new TestDriveService.BookRequestWrapper();
        w.zip       = '94043';
        w.vehicleId = 'placeholder';
        w.slotStart = String.valueOf(Datetime.now().addDays(1));
        w.slotEnd   = String.valueOf(Datetime.now().addDays(1).addHours(1));
        // no selectedSlotId — triggers 'Slot should be selected.' exception

        Test.startTest();
        List<TestDriveService.BookResponseWrapper> results =
            TestDriveService.invocableBookTestDrive(
                new List<TestDriveService.BookRequestWrapper>{ w }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].json.contains('Failed') || results[0].json.contains('Slot'));
    }

    // ── invocableBookTestDrive: capacity decremented after booking ────────────

    @IsTest
    static void testInvocable_CapacityDecremented() {
        TimeSlot__c slot = [SELECT Id, Capacity__c FROM TimeSlot__c LIMIT 1];
        Decimal originalCapacity = slot.Capacity__c;

        TestDriveService.BookRequestWrapper w = new TestDriveService.BookRequestWrapper();
        w.zip            = '94043';
        w.selectedSlotId = slot.Id;
        w.email          = 'cap.test@example.com';
        w.vehicleId      = 'placeholder';
        w.slotStart      = String.valueOf(Datetime.now().addDays(1));
        w.slotEnd        = String.valueOf(Datetime.now().addDays(1).addHours(1));

        Test.startTest();
        TestDriveService.invocableBookTestDrive(
            new List<TestDriveService.BookRequestWrapper>{ w }
        );
        Test.stopTest();

        TimeSlot__c updated = [SELECT Capacity__c FROM TimeSlot__c WHERE Id = :slot.Id];
        System.assertEquals(originalCapacity - 1, updated.Capacity__c, 'Capacity should be decremented by 1');
    }
}