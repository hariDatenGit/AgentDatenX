//
// TestDriveSlotSelector.cls
// Selector layer for Test Drive slot discovery via FSL
//
public with sharing class TestDriveSlotSelector {

    // NOTE: Current DTOs available = TestDriveDTOs.SlotDTO only (slotId, start, end1)
    // This class will return a list of SlotDTOs and a simple message map to stay compatible.

    public class GetSlotsResponse {
        @AuraEnabled public List<TestDriveDTOs.SlotDTO> options = new List<TestDriveDTOs.SlotDTO>();
        @AuraEnabled public String message;
    }

    public class SlotRequest {
        @AuraEnabled public String zip;
        @AuraEnabled public Id vehicleId;
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

    @InvocableMethod(label='Get Available Test Drive Slots' description='Returns available test drive slots as JSON')
    public static List<SlotsResponseWrapper> invocableGetAvailableSlots(List<SlotsRequestWrapper> payloads) {
        List<SlotsResponseWrapper> out = new List<SlotsResponseWrapper>();
        SlotsResponseWrapper r = new SlotsResponseWrapper();
        try {
            if (payloads == null || payloads.isEmpty()) {
                r.json = JSON.serialize(new GetSlotsResponse());
                out.add(r);
                return out;
            }
            SlotsRequestWrapper p = payloads[0];
            SlotRequest req = new SlotRequest();
            req.zip = p.zip;
            if (String.isNotBlank(p.vehicleId)) {
                try { req.vehicleId = (Id) p.vehicleId; } catch (Exception ignore) {}
            }
            if (String.isNotBlank(p.reqDate)) {
                try { req.reqDate = Date.valueOf(p.reqDate); } catch (Exception ignore) {}
            }
            req.maxResults = p.maxResults;
            req.timeWindow = p.timeWindow;

            GetSlotsResponse resp = getAvailableSlots(req);
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

            // 2) Resolve ZipTerritory__c (Active = true) ordered by Priority
            List<ZipTerritory__c> mappings = [
                SELECT Id, Zip__c, Dealer__c, Active__c, Priority__c,
                       Dealer__r.Id, Dealer__r.Name
                FROM ZipTerritory__c
                WHERE Active__c = true
                  AND Zip__c = :req.zip
                ORDER BY Priority__c ASC, CreatedDate ASC
                LIMIT 5
            ];
            if (mappings.isEmpty()) {
                throw new TestDriveServiceException('No dealer territory found for the given ZIP.');
            }

            // 3) Resolve territories: fallback to territories with OperatingHours
            List<ServiceTerritory> territories = [
                SELECT Id, Name, OperatingHoursId
                FROM ServiceTerritory
                WHERE OperatingHoursId != null
                ORDER BY CreatedDate ASC
                LIMIT 5
            ];
            if (territories.isEmpty()) {
                throw new TestDriveServiceException('No service territories with operating hours are configured.');
            }
            Set<Id> territoryIds = new Set<Id>();
            for (ServiceTerritory st : territories) {
                territoryIds.add(st.Id);
            }

            // 4) Build search window
            Map<Id, OperatingHours> opHoursByTer = fetchOperatingHours(territoryIds);
            Datetime windowStart;
            Datetime windowEnd;
            buildSearchWindow(req, opHoursByTer, windowStart, windowEnd);

            // 5) Query availability (heuristic without native FSL APIs)
            Integer slotMinutes = 60; // each test drive takes 60 minutes
            Integer stepMinutes = 30; // check candidate every 30 minutes

            Map<Id, List<TimeWindow>> busyByTerritory = queryBusyWindows(territoryIds, windowStart, windowEnd);

            List<TestDriveDTOs.SlotDTO> allOptions = new List<TestDriveDTOs.SlotDTO>();
            Integer maxResults = (req.maxResults == null || req.maxResults <= 0) ? 10 : req.maxResults;

            for (Id terrId : territoryIds) {
                List<TimeWindow> busy = busyByTerritory.containsKey(terrId) ? busyByTerritory.get(terrId) : new List<TimeWindow>();

                Datetime cursor = windowStart;
                Integer producedForTerr = 0;
                while (cursor < windowEnd && allOptions.size() < maxResults) {
                    Datetime candidateEnd = cursor.addMinutes(slotMinutes);
                    if (candidateEnd > windowEnd) break;

                    if (!overlapsBusy(cursor, candidateEnd, busy)) {
                        // Build a SlotDTO; slotId not used for now (can store composite key)
                        TestDriveDTOs.SlotDTO opt = new TestDriveDTOs.SlotDTO();
                        opt.slotId = null;
                        opt.start = cursor;
                        opt.end1 = candidateEnd;
                        allOptions.add(opt);
                        producedForTerr++;
                    }

                    cursor = cursor.addMinutes(stepMinutes);

                    // distribute fairly across territories
                    Integer fairCap = Math.max(1, (Integer)Math.floor(((Decimal)maxResults) / Math.max(1, territoryIds.size())));
                    if (producedForTerr >= fairCap) {
                        break; // move to next territory
                    }
                }
            }

            // Sort by start and trim
            allOptions.sort(new SlotStartAsc());
            if (allOptions.size() > maxResults) {
                List<TestDriveDTOs.SlotDTO> trimmed = new List<TestDriveDTOs.SlotDTO>();
                for (Integer i = 0; i < maxResults; i++) {
                    trimmed.add(allOptions[i]);
                }
                allOptions = trimmed;
            }

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

    // Simple time window holder
    private class TimeWindow {
        Datetime startDt;
        Datetime endDt;
        TimeWindow(Datetime s, Datetime e) { startDt = s; endDt = e; }
    }

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

    private static Map<Id, List<TimeWindow>> queryBusyWindows(Set<Id> territoryIds, Datetime winStart, Datetime winEnd) {
        Map<Id, List<TimeWindow>> result = new Map<Id, List<TimeWindow>>();
        if (territoryIds.isEmpty()) return result;

        List<ServiceAppointment> appts = [
            SELECT Id, ServiceTerritoryId, EarliestStartTime, DueDate, SchedStartTime, SchedEndTime, Status
            FROM ServiceAppointment
            WHERE ServiceTerritoryId IN :territoryIds
              AND (
                    (EarliestStartTime != null AND DueDate != null AND EarliestStartTime < :winEnd AND DueDate > :winStart) OR
                    (SchedStartTime != null AND SchedEndTime != null AND SchedStartTime < :winEnd AND SchedEndTime > :winStart)
                  )
              AND Status != 'Canceled'
        ];

        for (ServiceAppointment sa : appts) {
            Datetime s = (sa.SchedStartTime != null ? sa.SchedStartTime : sa.EarliestStartTime);
            Datetime e = (sa.SchedEndTime != null ? sa.SchedEndTime : sa.DueDate);
            if (s == null || e == null) continue;
            if (!result.containsKey(sa.ServiceTerritoryId)) {
                result.put(sa.ServiceTerritoryId, new List<TimeWindow>());
            }
            result.get(sa.ServiceTerritoryId).add(new TimeWindow(s, e));
        }

        // Merge overlaps per territory
        for (Id tid : new List<Id>(result.keySet())) {
            result.put(tid, mergeOverlaps(result.get(tid)));
        }
        return result;
    }

    private static List<TimeWindow> mergeOverlaps(List<TimeWindow> windows) {
        if (windows == null || windows.isEmpty()) return new List<TimeWindow>();
        // Use a named comparator to avoid parser issues
        windows.sort(new TimeWindowStartAsc());
        List<TimeWindow> merged = new List<TimeWindow>();
        TimeWindow curr = windows[0];
        for (Integer i = 1; i < windows.size(); i++) {
            TimeWindow next = windows[i];
            if (next.startDt <= curr.endDt) {
                if (next.endDt > curr.endDt) curr.endDt = next.endDt;
            } else {
                merged.add(curr);
                curr = next;
            }
        }
        merged.add(curr);
        return merged;
    }

    private static Boolean overlapsBusy(Datetime s, Datetime e, List<TimeWindow> busy) {
        if (busy == null) return false;
        for (TimeWindow w : busy) {
            if (s < w.endDt && e > w.startDt) return true;
        }
        return false;
    }

    // Named comparator used in mergeOverlaps
    private class TimeWindowStartAsc implements System.Comparator<TimeWindow> {
        public Integer compare(TimeWindow a, TimeWindow b) {
            if (a.startDt == b.startDt) return 0;
            return a.startDt < b.startDt ? -1 : 1;
        }
    }

    // Sorter for slot options by start ascending
    private class SlotStartAsc implements System.Comparator<TestDriveDTOs.SlotDTO> {
        public Integer compare(TestDriveDTOs.SlotDTO a, TestDriveDTOs.SlotDTO b) {
            if (a.start == b.start) return 0;
            return a.start < b.start ? -1 : 1;
        }
    }
}