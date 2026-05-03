// TestDriveSlotSelector.cls
// Selector layer for Test Drive slot discovery via FSL
//
public with sharing class TestDriveCustomSlotSelector {
     // NOTE: Current DTOs available = TestDriveDTOs.SlotDTO only (slotId, start, end1)
    // This class will return a list of SlotDTOs and a simple message map to stay compatible.

    public class GetSlotsResponse {
        @AuraEnabled public List<TestDriveDTOs.SlotDTO> options = new List<TestDriveDTOs.SlotDTO>();
        @AuraEnabled public String message;
    }
 
    public class SlotRequest {
        @AuraEnabled public String zip;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public Date reqDate;
        @AuraEnabled public Integer maxResults;
        @AuraEnabled public String timeWindow; // Morning | Afternoon | Evening | null
    }

    // Strongly-typed Invocable wrapper (preferred for action discovery)
    public class SlotsRequestWrapper {
        @InvocableVariable(required=true) public String zip;
        @InvocableVariable(required=true) public String reqDate; // YYYY-MM-DD
        @InvocableVariable(required=false) public String vehicleId;
        @InvocableVariable(required=false) public Integer maxResults;
        @InvocableVariable(required=false) public String timeWindow; // Morning|Afternoon|Evening
    }
    public class SlotsResponseWrapper {
        @InvocableVariable(required=false) public String json; // JSON(GetSlotsResponse)
    }

    @InvocableMethod(label='Get Custom Available Test Drive Slots' description='Returns available test drive slots as JSON')
    public static List<SlotsResponseWrapper> invocableGetAvailableSlots(List<SlotsRequestWrapper> payloads) {
        List<SlotsResponseWrapper> out = new List<SlotsResponseWrapper>();
        SlotsResponseWrapper r = new SlotsResponseWrapper();
        System.debug('payloads =======> ' + payloads);
        try {
            if (payloads == null || payloads.isEmpty()) {
                r.json = JSON.serialize(new GetSlotsResponse());
                out.add(r);
                return out;
            }
            SlotsRequestWrapper p = payloads[0];
            SlotRequest req = new SlotRequest();
            req.zip = p.zip;
            System.debug('payloads 11=======> ' + p);
            if (String.isNotBlank(p.vehicleId)) {
                try { req.vehicleName = p.vehicleId; } catch (Exception ignore) {}
            }
            if (String.isNotBlank(p.reqDate)) {
                try { req.reqDate = Date.valueOf(p.reqDate); } catch (Exception ignore) {}
            }
            req.maxResults = p.maxResults;
            req.timeWindow = p.timeWindow;
            System.debug('req =======> ' + req);
            GetSlotsResponse resp = getAvailableSlots(req);
            System.debug('resp =======> ' + resp);
            r.json = JSON.serialize(resp);
            out.add(r);
            return out;
        } catch (Exception e) {
            GetSlotsResponse err = new GetSlotsResponse();
            err.message = 'Failed to process request: ' + e.getMessage();
            r.json = JSON.serialize(err);
            out.add(r);
            return out;
        }
    }

    @AuraEnabled(cacheable=true)
    public static GetSlotsResponse getAvailableSlots(SlotRequest req) {
        try {
            // 1) Validate and normalize
            if (req == null) {
                throw new TestDriveServiceException('Request is required.');
            }
            normalizeRequest(req);
            validateRequest(req);

            // 2) Resolve Time slot fo Active vehicals (Active = true) ordered by Priority
            List<TimeSlot__c> availableSlots = [SELECT Dealer__c, Date__c, Vehicle__c, StartTime__c, EndTime__c, Status__c, 
                Capacity__c, Dealer__r.BillingPostalCode, Vehicle__r.Name FROM TimeSlot__c 
                WHERE Dealer__r.BillingPostalCode =:req.zip  AND Vehicle__r.Name =:req.vehicleName 
                AND Date__c =:req.reqDate AND Status__c ='Available' AND Capacity__c > 0 LIMIT 50 ];
            if (availableSlots.isEmpty()) {
                throw new TestDriveServiceException('No dealer territory found for the given ZIP.');
            }
            List<TestDriveDTOs.SlotDTO> allOptions = new List<TestDriveDTOs.SlotDTO>();
            Integer maxResults = (req.maxResults == null || req.maxResults <= 0) ? 10 : req.maxResults;
            for(TimeSlot__c slot : availableSlots){
                 TestDriveDTOs.SlotDTO opt = new TestDriveDTOs.SlotDTO();
                        opt.slotId = slot.Id;
                        opt.startTime = slot.StartTime__c;
                        opt.endTime = slot.EndTime__c;
                        allOptions.add(opt);
            }
            System.debug('allOptions 1111=======> ' + allOptions);
            // Sort by start and trim
            allOptions.sort(new SlotStartAsc());
            if (allOptions.size() > maxResults) {
                List<TestDriveDTOs.SlotDTO> trimmed = new List<TestDriveDTOs.SlotDTO>();
                for (Integer i = 0; i < maxResults; i++) {
                    trimmed.add(allOptions[i]);
                }
                allOptions = trimmed;
            }
            System.debug('allOptions 222=======> ' + allOptions);
            GetSlotsResponse resp = new GetSlotsResponse();
            resp.options = allOptions;
            resp.message = allOptions.isEmpty() ? 'No available slots found in the requested window. Try a different time/date.' : 'Success';
            return resp;

        } catch (TestDriveServiceException ex) {
            throw ex;
        } catch (Exception e) {
            throw new TestDriveServiceException('Failed to discover available slots: ' + e.getMessage());
        }
    }

    // Normalize zip and defaults
    private static void normalizeRequest(SlotRequest req) {
        if (req.zip != null) req.zip = req.zip.replaceAll('[^0-9A-Za-z]', '').toUpperCase();
        if (req.maxResults == null || req.maxResults <= 0) req.maxResults = 10;
    }

    private static void validateRequest(SlotRequest req) {
        if (String.isBlank(req.zip)) {
            throw new TestDriveServiceException('ZIP is required.');
        }
        if (req.reqDate == null) {
            throw new TestDriveServiceException('Date is required.');
        }
        Date today = Date.today();
        if (req.reqDate < today) {
            throw new TestDriveServiceException('Date must not be in the past.');
        }
        if (req.reqDate > today.addDays(30)) {
            throw new TestDriveServiceException('Date must be within the next 30 days.');
        }
    }

    
    @TestVisible
    private static Map<Id, OperatingHours> fetchOperatingHours(Set<Id> territoryIds) {
        Map<Id, OperatingHours> result = new Map<Id, OperatingHours>();
        if (territoryIds.isEmpty()) return result;

        Map<Id, ServiceTerritory> terToHours = new Map<Id, ServiceTerritory>([
            SELECT Id, OperatingHoursId
            FROM ServiceTerritory
            WHERE Id IN :territoryIds
        ]);

        Set<Id> opHoursIds = new Set<Id>();
        for (ServiceTerritory st : terToHours.values()) {
            if (st.OperatingHoursId != null) opHoursIds.add(st.OperatingHoursId);
        }

        Map<Id, OperatingHours> hoursById = new Map<Id, OperatingHours>();
        if (!opHoursIds.isEmpty()) {
            hoursById = new Map<Id, OperatingHours>([
                SELECT Id, Name
                FROM OperatingHours
                WHERE Id IN :opHoursIds
            ]);
        }

        for (Id terrId : territoryIds) {
            ServiceTerritory st = terToHours.get(terrId);
            if (st != null && st.OperatingHoursId != null && hoursById.containsKey(st.OperatingHoursId)) {
                result.put(terrId, hoursById.get(st.OperatingHoursId));
            }
        }
        return result;
    }

    @TestVisible
    private static void buildSearchWindow(SlotRequest req, Map<Id, OperatingHours> opHoursByTer, Datetime windowStart, Datetime windowEnd) {
        // Default 9:00 to 17:00
        Time startT = Time.newInstance(9, 0, 0, 0);
        Time endT = Time.newInstance(17, 0, 0, 0);

        if (req.timeWindow != null) {
            String tw = req.timeWindow != null ? req.timeWindow.toLowerCase() : null;
            if (tw == 'morning') {
                startT = Time.newInstance(9, 0, 0, 0);
                endT = Time.newInstance(12, 0, 0, 0);
            } else if (tw == 'afternoon') {
                startT = Time.newInstance(12, 0, 0, 0);
                endT = Time.newInstance(16, 0, 0, 0);
            } else if (tw == 'evening') {
                startT = Time.newInstance(16, 0, 0, 0);
                endT = Time.newInstance(19, 0, 0, 0);
            }
        }

        windowStart = Datetime.newInstance(req.reqDate, startT);
        windowEnd = Datetime.newInstance(req.reqDate, endT);
    }

  
    // Sorter for slot options by start ascending
    private class SlotStartAsc implements System.Comparator<TestDriveDTOs.SlotDTO> {
        public Integer compare(TestDriveDTOs.SlotDTO a, TestDriveDTOs.SlotDTO b) {
            if (a.startTime == b.startTime) return 0;
            return a.startTime < b.startTime ? -1 : 1;
        }
    }
}