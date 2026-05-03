@IsTest
private class TestDriveDTOsTest {

    // ── No-arg constructor ────────────────────────────────────────────────────

    @IsTest
    static void testSlotDTO_NoArgConstructor() {
        TestDriveDTOs.SlotDTO dto = new TestDriveDTOs.SlotDTO();

        System.assertEquals(null, dto.slotId);
        System.assertEquals(null, dto.start);
        System.assertEquals(null, dto.end1);
        System.assertEquals(null, dto.startTime);
        System.assertEquals(null, dto.endTime);
    }

    // ── Datetime constructor ──────────────────────────────────────────────────

    @IsTest
    static void testSlotDTO_DatetimeConstructor() {
        Account acc = new Account(Name = 'DTO Test Dealer');
        insert acc;
        // Use Account Id as a valid Id value for slotId
        Id fakeSlotId = acc.Id;

        Datetime start = Datetime.newInstance(2025, 8, 1, 9, 0, 0);
        Datetime end1  = Datetime.newInstance(2025, 8, 1, 10, 0, 0);

        Test.startTest();
        TestDriveDTOs.SlotDTO dto = new TestDriveDTOs.SlotDTO(fakeSlotId, start, end1);
        Test.stopTest();

        System.assertEquals(fakeSlotId, dto.slotId);
        System.assertEquals(start, dto.start);
        System.assertEquals(end1, dto.end1);
        System.assertEquals(null, dto.startTime);
        System.assertEquals(null, dto.endTime);
    }

    // ── Time constructor ──────────────────────────────────────────────────────

    @IsTest
    static void testSlotDTO_TimeConstructor() {
        Account acc = new Account(Name = 'DTO Test Dealer 2');
        insert acc;
        Id fakeSlotId = acc.Id;

        Time startTime = Time.newInstance(9, 0, 0, 0);
        Time endTime   = Time.newInstance(10, 0, 0, 0);

        Test.startTest();
        TestDriveDTOs.SlotDTO dto = new TestDriveDTOs.SlotDTO(fakeSlotId, startTime, endTime);
        Test.stopTest();

        System.assertEquals(fakeSlotId, dto.slotId);
        System.assertEquals(startTime, dto.startTime);
        System.assertEquals(endTime, dto.endTime);
        System.assertEquals(null, dto.start);
        System.assertEquals(null, dto.end1);
    }

    // ── Field assignment via no-arg constructor ───────────────────────────────

    @IsTest
    static void testSlotDTO_FieldAssignment() {
        Account acc = new Account(Name = 'DTO Test Dealer 3');
        insert acc;

        Datetime start     = Datetime.newInstance(2025, 9, 1, 14, 0, 0);
        Datetime end1      = Datetime.newInstance(2025, 9, 1, 15, 0, 0);
        Time startTime     = Time.newInstance(14, 0, 0, 0);
        Time endTime       = Time.newInstance(15, 0, 0, 0);

        TestDriveDTOs.SlotDTO dto = new TestDriveDTOs.SlotDTO();
        dto.slotId    = acc.Id;
        dto.start     = start;
        dto.end1      = end1;
        dto.startTime = startTime;
        dto.endTime   = endTime;

        System.assertEquals(acc.Id, dto.slotId);
        System.assertEquals(start, dto.start);
        System.assertEquals(end1, dto.end1);
        System.assertEquals(startTime, dto.startTime);
        System.assertEquals(endTime, dto.endTime);
    }
}