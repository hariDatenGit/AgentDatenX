/**
 * DTO container for Test Drive scheduling features.
 * Provides lightweight structures for agent action responses.
 */
public with sharing class TestDriveDTOs {
    /**
     * Represents an available slot for a test drive.
     * Fields are designed to serialize cleanly for Agentforce actions.
     */
    public class SlotDTO {
        @AuraEnabled public Id slotId;
        @AuraEnabled public Datetime start;
        @AuraEnabled public Datetime end1;
        @AuraEnabled public Time  startTime;
        @AuraEnabled public Time endTime;
        public SlotDTO() {} 

        public SlotDTO(Id slotId, Datetime start, Datetime end1) {
            this.slotId = slotId;
            this.start = start;
            this.end1 = end1;
        }
        public SlotDTO(Id slotId, Time startTime, Time endTime) {
            this.slotId = slotId;
            this.startTime = startTime;
            this.endTime = endTime;
        }
    }
}