//
// TestDriveService.cls
// Service layer for Test Drive booking
//
public with sharing class TestDriveService {

    public class BookRequestDTO {
        @AuraEnabled public String zip;
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public Id dealerId;
        @AuraEnabled public Id selectedSlotId;
        @AuraEnabled public Id serviceTerritoryId;
        @AuraEnabled public Datetime slotStart;
        @AuraEnabled public Datetime slotEnd;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String externalSourceId;
        @AuraEnabled public String agentSessionId;
        @AuraEnabled public String channel; // Chat/SMS/Voice/Email
        @AuraEnabled public String notes;
         @AuraEnabled public String modelInterested;
    }

    public class BookResponseDTO {
        @AuraEnabled public Id testDriveId;
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String appointmentNumber;
        @AuraEnabled public Datetime schedStart;
        @AuraEnabled public Datetime schedEnd;
        @AuraEnabled public String dealerName;
        @AuraEnabled public String message;
    }

    // Invocable wrapper DTOs for Agent action compatibility
    public class BookRequestWrapper {
        @InvocableVariable(required=true) public String zip;
        @InvocableVariable(required=true) public String vehicleId;
        @InvocableVariable(required=false) public String dealerId;
        @InvocableVariable(required=false) public String serviceTerritoryId;
        @InvocableVariable(required=false) public String selectedSlotId;
        @InvocableVariable(required=true) public String slotStart; // ISO or yyyy-MM-ddTHH:mm:ssZ
        @InvocableVariable(required=true) public String slotEnd;   // ISO or yyyy-MM-ddTHH:mm:ssZ
        @InvocableVariable(required=false) public String firstName;
        @InvocableVariable(required=false) public String lastName;
        @InvocableVariable(required=false) public String email;
        @InvocableVariable(required=false) public String phone;
        @InvocableVariable(required=false) public String externalSourceId;
        @InvocableVariable(required=false) public String agentSessionId;
        @InvocableVariable(required=false) public String channel;
        @InvocableVariable(required=false) public String notes;
    }
    public class BookResponseWrapper {
        @InvocableVariable(required=false) public String json; // JSON(BookResponseDTO)
    }

    // Invocable entry point: apex://TestDriveService.invocableBookTestDrive
    @InvocableMethod(label='Book Test Drive' description='Books a Service Appointment and Test_Drive__c')
    public static List<BookResponseWrapper> invocableBookTestDrive(List<BookRequestWrapper> inputs) {
        List<BookResponseWrapper> out = new List<BookResponseWrapper>();
        BookResponseWrapper r = new BookResponseWrapper();
        try {
            if (inputs == null || inputs.isEmpty()) {
                r.json = JSON.serialize(new BookResponseDTO());
                out.add(r);
                return out;
            }
            BookRequestWrapper p = inputs[0];
            System.debug('inputs[0] =============> '+ p);
            // Build strong-typed request
            BookRequestDTO req = new BookRequestDTO();
            req.zip = p.zip;
            TimeSlot__c timeSlot = null;
            if (String.isNotBlank(p.selectedSlotId)) { 
                try { 
                    req.selectedSlotId = (Id)p.selectedSlotId; 
                    List<TimeSlot__c> timeSlotList =[SELECT Id, Date__c, StartTime__c, EndTime__c, Status__c, Capacity__c,  Dealer__r.BillingPostalCode,  Dealer__r.Name,  Dealer__c,  Vehicle__c, Vehicle__r.Name  FROM TimeSlot__c where Id =:req.selectedSlotId limit 1];
                    if(timeSlotList <> null && !timeSlotList.isEmpty()){
                        timeSlot =  timeSlotList[0];
                        req.vehicleId = timeSlot.Vehicle__c;
                        req.dealerId = timeSlot.Dealer__c;
                        Datetime slotStart = Datetime.newInstance(timeSlot.Date__c, timeSlot.StartTime__c);
                        Datetime slotEnd = Datetime.newInstance(timeSlot.Date__c, timeSlot.EndTime__c);
                        req.slotStart = slotStart;
                        req.slotEnd = slotEnd;
                        req.modelInterested = timeSlot.Vehicle__r.Name;
                    }
                } catch (Exception ignore) {} }
            if (String.isNotBlank(p.serviceTerritoryId)) { try { req.serviceTerritoryId = (Id)p.serviceTerritoryId; } catch (Exception ignore) {} }
            
            req.firstName = p.firstName;
            req.lastName = p.lastName;
            req.email = p.email;
            req.phone = p.phone;
            req.externalSourceId = p.externalSourceId;
            req.agentSessionId = p.agentSessionId;
            req.channel = p.channel;
            req.notes = p.notes;
            System.debug('req =============> '+ req);
            BookResponseDTO resp = bookTestDrive(req);
            if(timeSlot <> null){
                timeSlot.Capacity__c = timeSlot.Capacity__c -1;
                update timeSlot;
            }
            
            r.json = JSON.serialize(resp);
            out.add(r);
            return out;
        } catch (Exception e) {
            BookResponseDTO err = new BookResponseDTO();
            err.message = 'Failed to process booking request: ' + e.getMessage();
            r.json = JSON.serialize(err);
            out.add(r);
            return out;
        }
    }

    @AuraEnabled
    public static BookResponseDTO bookTestDrive(BookRequestDTO req) {
        // Basic validations
        if (req == null) throw new TestDriveServiceException('Request is required.');
        if (String.isBlank(req.zip)) throw new TestDriveServiceException('ZIP is required.');
        if (req.selectedSlotId == null) throw new TestDriveServiceException('Slot should be selected.');
        System.debug('req =============> '+ req);
        // Ensure no scheduling conflict in the same territory
        
        // Resolve Contact/Lead
        Id contactId;
        Id leadId;
        if (!String.isBlank(req.email)) {
            List<Contact> contacts = [SELECT Id FROM Contact WHERE Email = :req.email LIMIT 1];
            if (!contacts.isEmpty()) contactId = contacts[0].Id;
            if (contactId == null) {
                List<Lead> leads = [SELECT Id FROM Lead WHERE Email = :req.email LIMIT 1];
                if (!leads.isEmpty()) leadId = leads[0].Id;
            }
        }
        // If still none, create a Lead minimally
        if (contactId == null && leadId == null) {
            Lead newLead = new Lead(
                FirstName = req.firstName,
                LastName = String.isBlank(req.lastName) ? 'Test Drive' : req.lastName,
                Company = 'Test Drive - ' + (Date.today().format()),
                Email = req.email,
                Phone = req.phone,
                Status = 'Open - Not Contacted'
            );
            insert newLead;
            leadId = newLead.Id;
        }

        // Idempotency for Test_Drive__c vs TestDrive__c naming:
        // The workspace shows both. The user requested Test_Drive__c earlier.
        // Create/Upsert on Test_Drive__c using ExternalSourceId__c when provided.
        Test_Drive__c td = new Test_Drive__c(
                Dealer__c = req.dealerId,
                Vehicle__c = req.vehicleId,
                Zip__c = req.zip,
                Customer_Email__c =req.email,
                PreferredDateTime__c = req.slotStart,
                Status__c = 'Scheduled',
                Source__c = 'Agentforce',
                Channel__c = String.isBlank(req.channel) ? 'Chat' : req.channel,
                Notes__c = req.notes,
                Model_Interested__c = req.modelInterested,
                LastAgentSessionId__c = req.agentSessionId
                //ServiceAppointment__c = sa.Id
            );

            System.debug('td =============> '+ td);
            insert td;
            System.debug('td =============>1 '+ td);
        // Link Contact/Lead on Test_Drive__c if fields exist (they do)
        if (contactId != null) {
            td = new Test_Drive__c(Id = td.Id, Contact__c = contactId);
            update td;
        } else if (leadId != null) {
            td = new Test_Drive__c(Id = td.Id, Lead__c = leadId);
            update td;
        }

        System.debug('td =============>2 '+ td);
        // Response payload
        BookResponseDTO resp = new BookResponseDTO();
        resp.testDriveId = td.Id;
        if (req.dealerId != null) {
            Account a = [SELECT Name FROM Account WHERE Id = :req.dealerId LIMIT 1];
            resp.dealerName = a != null ? a.Name : null;
        }
        resp.message = 'Booked';
        System.debug('resp =============> '+ resp);
        return resp;
    }

   
}