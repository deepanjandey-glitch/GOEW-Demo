/**
 * Backs the "Create Booking" tab (LWC: createBooking).
 * Mirrors the record creation done by the "Create Booking from Enquiry" flow, but starts
 * from a primary guest instead of an Enquiry. All contacts, the booking and its related
 * records are created in a single transaction.
 */
public with sharing class CreateBookingController {

    private static final Integer MIN_SEARCH_LENGTH = 2;
    private static final Integer MAX_NAME_LENGTH = 80;
    private static final Integer MAX_PASSPORT_LENGTH = 10;
    private static final String PAN_PATTERN = '[A-Z]{5}[0-9]{4}[A-Z]{1}';
    private static final String STATUS_SEND_FOR_APPROVAL = 'Send for approval';
    private static final String STATUS_APPROVED = 'Approved';

    // ---------------------------------------------------------------------------------
    // Lookups
    // ---------------------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchKey, List<Id> excludeIds) {
        String key = searchKey == null ? '' : searchKey.trim();
        if (key.length() < MIN_SEARCH_LENGTH) {
            return new List<Contact>();
        }
        String likeKey = '%' + key + '%';
        List<Id> excluded = excludeIds == null ? new List<Id>() : excludeIds;
        return [
            SELECT Id, Name, Salutation, FirstName, LastName, MobilePhone, Email,
                   Passport_Number__c, Date_Of_Issue__c, Date_Of_Expiry__c
            FROM Contact
            WHERE (Name LIKE :likeKey OR MobilePhone LIKE :likeKey OR Email LIKE :likeKey
                   OR Passport_Number__c LIKE :likeKey)
              AND Id NOT IN :excluded
            ORDER BY Name
            LIMIT 10
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Tour_Master__c> getTourMasters() {
        return [SELECT Id, Name, FOREX_Type__c FROM Tour_Master__c ORDER BY Name];
    }

    @AuraEnabled(cacheable=true)
    public static List<Tour_Plan__c> getTourPlans(Id tourMasterId) {
        if (tourMasterId == null) {
            return new List<Tour_Plan__c>();
        }
        return [
            SELECT Id, Name, Season__c, Start_Date__c, End_Date__c, Cost_INR__c, Cost_in_Forex__c,
                   Single__c, Double_Tuwin_Triple__c, Child_With_Bed__c, Child_Without_Bed__c,
                   FOREX_Type__c, Predefined_Standard_Discount__c, Predefined_Special_Discount__c
            FROM Tour_Plan__c
            WHERE Tour_Master__c = :tourMasterId
            ORDER BY Start_Date__c DESC NULLS LAST, Name
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Optional_Tour__c> getOptionalTours(Id tourMasterId) {
        if (tourMasterId == null) {
            return new List<Optional_Tour__c>();
        }
        return [
            SELECT Id, Name, Cost__c, Description__c
            FROM Optional_Tour__c
            WHERE Tour_Master__c = :tourMasterId
            ORDER BY Name
        ];
    }

    // ---------------------------------------------------------------------------------
    // Booking creation
    // ---------------------------------------------------------------------------------

    @AuraEnabled
    public static Id createBooking(String requestJson) {
        BookingRequest req;
        try {
            req = (BookingRequest) JSON.deserialize(requestJson, BookingRequest.class);
        } catch (Exception e) {
            throw error('The booking request could not be read. Please refresh the page and try again.');
        }
        if (req == null) {
            throw error('The booking request is empty.');
        }

        List<GuestInput> guests = collectGuests(req);
        Tour_Plan__c plan = validateRequest(req, guests);
        List<Optional_Tour__c> optionalTours = getSelectedOptionalTours(req, plan);

        Savepoint sp = Database.setSavepoint();
        try {
            // Index-aligned with guests; index 0 is the primary guest
            List<Contact> guestContacts = resolveContacts(guests);
            Contact primaryContact = guestContacts[0];

            // Same format as the flow's BookingName formula: <guest name>-<d>/<m>/<yy of tour start>
            String bookingName = truncate(fullName(primaryContact), MAX_NAME_LENGTH - 9) + '-' + formatStartDate(plan.Start_Date__c);

            Decimal optionalTourCost = 0;
            for (Optional_Tour__c ot : optionalTours) {
                optionalTourCost += ot.Cost__c == null ? 0 : ot.Cost__c;
            }

            Boolean isAddition = req.additionInTourCost == true;
            Boolean isReduction = req.reductionInTourCost == true;

            Booking__c booking = new Booking__c(
                Name = bookingName,
                Contact__c = primaryContact.Id,
                Tour_Plan__c = plan.Id,
                FOREX_Type__c = bookingForexType(plan.FOREX_Type__c),
                Exchange_Rate__c = req.exchangeRate,
                // As in the flow: a reduction in tour cost needs approval, everything else is approved
                Booking_Status__c = isReduction ? STATUS_SEND_FOR_APPROVAL : STATUS_APPROVED,
                Addition_in_Tour_Cost__c = isAddition,
                INR_Component__c = isAddition ? nz(req.inrAddition) : 0,
                FOREX_Component__c = isAddition ? nz(req.forexAddition) : 0,
                Reduction_in_Tour_Cost__c = isReduction,
                INR_Component_Reduction__c = isReduction ? nz(req.inrReduction) : 0,
                FOREX_Component_Reduction__c = isReduction ? nz(req.forexReduction) : 0,
                Standard_Discount__c = nz(req.standardDiscount),
                Special_Discount__c = nz(req.specialDiscount),
                Optional_Tour__c = !optionalTours.isEmpty(),
                Optional_Tour_Cost__c = optionalTourCost,
                Nominee_Name__c = req.nomineeName,
                Nominee_Contact_Number__c = req.nomineeContactNumber,
                Relation_with_Nominee__c = req.relationWithNominee,
                Remarks__c = req.remarks
            );
            insert booking;

            List<Customer_Booking_List__c> bookingLists = new List<Customer_Booking_List__c>();
            for (Integer i = 0; i < guests.size(); i++) {
                GuestInput guest = guests[i];
                Contact c = guestContacts[i];
                Boolean isPrimary = i == 0;
                bookingLists.add(new Customer_Booking_List__c(
                    Name = truncate(isPrimary ? bookingName : bookingName + '-' + fullName(c), MAX_NAME_LENGTH),
                    Booking__c = booking.Id,
                    Customer__c = c.Id,
                    Room_Type__c = guest.roomType,
                    Meal_Preference__c = String.isBlank(guest.mealPreference) ? null : guest.mealPreference
                ));
            }
            insert bookingLists;

            if (!optionalTours.isEmpty()) {
                List<Booking_Optional_Tour__c> bookingOptionalTours = new List<Booking_Optional_Tour__c>();
                for (Optional_Tour__c ot : optionalTours) {
                    bookingOptionalTours.add(new Booking_Optional_Tour__c(
                        Name = truncate(bookingName + '-' + ot.Name, MAX_NAME_LENGTH),
                        Booking__c = booking.Id,
                        Optional_Tour__c = ot.Id
                    ));
                }
                insert bookingOptionalTours;
            }

            return booking.Id;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw error(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw error(e.getMessage());
        }
    }

    // ---------------------------------------------------------------------------------
    // Validation
    // ---------------------------------------------------------------------------------

    private static List<GuestInput> collectGuests(BookingRequest req) {
        if (req.primaryGuest == null || (req.primaryGuest.contactId == null && req.primaryGuest.newContact == null)) {
            throw error('Select or create the Primary Guest.');
        }
        List<GuestInput> guests = new List<GuestInput>{ req.primaryGuest };
        if (req.paxGuests != null) {
            Integer index = 1;
            for (GuestInput pax : req.paxGuests) {
                if (pax == null || (pax.contactId == null && pax.newContact == null)) {
                    throw error('Select or create a contact for PAX ' + index + '.');
                }
                guests.add(pax);
                index++;
            }
        }
        return guests;
    }

    private static Tour_Plan__c validateRequest(BookingRequest req, List<GuestInput> guests) {
        Set<Id> contactIds = new Set<Id>();
        Set<String> newPassports = new Set<String>();
        for (Integer i = 0; i < guests.size(); i++) {
            GuestInput guest = guests[i];
            Boolean isPrimary = i == 0;
            String who = isPrimary ? 'Primary Guest' : 'PAX ' + i;
            if (String.isBlank(guest.roomType)) {
                throw error('Room Type is required for ' + who + '.');
            }
            if (guest.contactId != null) {
                if (!contactIds.add(guest.contactId)) {
                    throw error('The same contact has been added more than once (' + who + ').');
                }
            } else {
                validateNewContact(guest.newContact, isPrimary, who);
                String passport = guest.newContact.passportNumber.trim().toUpperCase();
                if (!newPassports.add(passport)) {
                    throw error('Passport Number ' + passport + ' has been entered for more than one new contact.');
                }
            }
        }

        if (!newPassports.isEmpty()) {
            List<Contact> existing = [
                SELECT Id, Name, Passport_Number__c FROM Contact WHERE Passport_Number__c IN :newPassports LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw error('A contact with Passport Number ' + existing[0].Passport_Number__c + ' already exists ('
                    + existing[0].Name + '). Search and select the existing contact instead of creating a new one.');
            }
        }

        if (req.tourPlanId == null) {
            throw error('Select a Tour Plan.');
        }
        if (String.isBlank(req.nomineeName)) {
            throw error('Nominee Name is required.');
        }
        if (String.isBlank(req.relationWithNominee)) {
            throw error('Relation with Nominee is required.');
        }
        List<Tour_Plan__c> plans = [
            SELECT Id, Name, Start_Date__c, Tour_Master__c, FOREX_Type__c,
                   Predefined_Standard_Discount__c, Predefined_Special_Discount__c
            FROM Tour_Plan__c WHERE Id = :req.tourPlanId LIMIT 1
        ];
        if (plans.isEmpty()) {
            throw error('The selected Tour Plan no longer exists.');
        }
        Tour_Plan__c plan = plans[0];
        if (req.tourMasterId != null && plan.Tour_Master__c != req.tourMasterId) {
            throw error('The selected Tour Plan does not belong to the selected Tour Master.');
        }

        if (req.additionInTourCost == true) {
            validateAdjustment(req.inrAddition, req.forexAddition, 'Addition in Tour Cost');
        }
        if (req.reductionInTourCost == true) {
            validateAdjustment(req.inrReduction, req.forexReduction, 'Reduction in Tour Cost');
        }

        if (req.exchangeRate != null && req.exchangeRate <= 0) {
            throw error('Exchange Rate must be greater than 0.');
        }

        validateDiscount(req.standardDiscount, plan.Predefined_Standard_Discount__c, 'Standard Discount');
        validateDiscount(req.specialDiscount, plan.Predefined_Special_Discount__c, 'Special Discount');

        // Duplicate check (the flow blocks a second booking for the same guest on the same tour)
        Id primaryContactId = req.primaryGuest.contactId;
        if (primaryContactId != null) {
            List<Booking__c> duplicates = [
                SELECT Id, Name FROM Booking__c
                WHERE Contact__c = :primaryContactId AND Tour_Plan__c = :plan.Id
                  AND Booking_Status__c != 'Rejected'
                LIMIT 1
            ];
            if (!duplicates.isEmpty()) {
                throw error('A booking already exists for this Primary Guest on the selected Tour Plan: '
                    + duplicates[0].Name + '.');
            }
        }
        return plan;
    }

    private static void validateNewContact(NewContactInput c, Boolean isPrimary, String who) {
        if (c == null) {
            throw error('Contact details are missing for ' + who + '.');
        }
        List<String> missing = new List<String>();
        if (String.isBlank(c.salutation)) missing.add('Salutation');
        if (String.isBlank(c.firstName)) missing.add('First Name');
        if (String.isBlank(c.lastName)) missing.add('Last Name');
        if (c.dateOfBirth == null) missing.add('Date of Birth');
        // Mobile and PAN are mandatory for the primary guest only
        if (isPrimary && String.isBlank(c.mobile)) missing.add('Mobile');
        if (isPrimary && String.isBlank(c.pan)) missing.add('PAN');
        if (String.isBlank(c.passportNumber)) missing.add('Passport Number');
        if (c.dateOfIssue == null) missing.add('Date of Issue');
        if (c.dateOfExpiry == null) missing.add('Date of Expiry');
        if (!missing.isEmpty()) {
            throw error('Missing details for ' + who + ': ' + String.join(missing, ', ') + '.');
        }
        if (String.isNotBlank(c.pan) && !Pattern.matches(PAN_PATTERN, c.pan.trim().toUpperCase())) {
            throw error('Please check the PAN No. for ' + who + ' (format: ABCDE1234F).');
        }
        if (c.passportNumber.trim().length() > MAX_PASSPORT_LENGTH) {
            throw error('Please provide a valid Passport Number for ' + who + ' (max ' + MAX_PASSPORT_LENGTH + ' characters).');
        }
        if (c.dateOfBirth > Date.today()) {
            throw error('Date of Birth cannot be in the future for ' + who + '.');
        }
        if (c.dateOfExpiry <= c.dateOfIssue) {
            throw error('Date of Expiry must be after Date of Issue for ' + who + '.');
        }
    }

    private static void validateAdjustment(Decimal inr, Decimal forex, String label) {
        if ((inr == null || inr == 0) && (forex == null || forex == 0)) {
            throw error('Enter the INR and/or Forex component for ' + label + '.');
        }
        if ((inr != null && inr < 0) || (forex != null && forex < 0)) {
            throw error(label + ' values cannot be negative.');
        }
    }

    private static void validateDiscount(Decimal value, Decimal maxValue, String label) {
        Decimal max = nz(maxValue);
        Decimal v = nz(value);
        if (v < 0 || v > max) {
            throw error(label + ' must be between 0 and ' + max.format() + '.');
        }
    }

    private static List<Optional_Tour__c> getSelectedOptionalTours(BookingRequest req, Tour_Plan__c plan) {
        if (req.optionalTourIds == null || req.optionalTourIds.isEmpty()) {
            return new List<Optional_Tour__c>();
        }
        List<Optional_Tour__c> tours = [
            SELECT Id, Name, Cost__c FROM Optional_Tour__c
            WHERE Id IN :req.optionalTourIds AND Tour_Master__c = :plan.Tour_Master__c
        ];
        if (tours.size() != new Set<Id>(req.optionalTourIds).size()) {
            throw error('One or more selected Optional Tours are not available for this Tour Master.');
        }
        return tours;
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static List<Contact> resolveContacts(List<GuestInput> guests) {
        List<Contact> guestContacts = new List<Contact>();
        Set<Id> existingIds = new Set<Id>();
        List<Contact> newContacts = new List<Contact>();

        for (GuestInput guest : guests) {
            if (guest.contactId != null) {
                existingIds.add(guest.contactId);
                guestContacts.add(null);
            } else {
                NewContactInput n = guest.newContact;
                Contact c = new Contact(
                    Salutation = n.salutation,
                    FirstName = n.firstName.trim(),
                    LastName = n.lastName.trim(),
                    MobilePhone = String.isBlank(n.mobile) ? null : n.mobile.trim(),
                    PAN_Number__c = String.isBlank(n.pan) ? null : n.pan.trim().toUpperCase(),
                    Date_Of_Birth__c = n.dateOfBirth,
                    Passport_Number__c = n.passportNumber.trim().toUpperCase(),
                    Date_Of_Issue__c = n.dateOfIssue,
                    Date_Of_Expiry__c = n.dateOfExpiry
                );
                newContacts.add(c);
                guestContacts.add(c);
            }
        }

        if (!newContacts.isEmpty()) {
            insert newContacts;
        }

        if (!existingIds.isEmpty()) {
            Map<Id, Contact> existing = new Map<Id, Contact>(
                [SELECT Id, FirstName, LastName FROM Contact WHERE Id IN :existingIds]
            );
            for (Integer i = 0; i < guests.size(); i++) {
                Id contactId = guests[i].contactId;
                if (contactId == null) {
                    continue;
                }
                Contact c = existing.get(contactId);
                if (c == null) {
                    throw error('One of the selected contacts no longer exists or is not accessible.');
                }
                guestContacts[i] = c;
            }
        }
        return guestContacts;
    }

    /** Booking__c.FOREX_Type__c is a restricted picklist; only copy the tour's forex type when it is a valid value */
    private static String bookingForexType(String forexType) {
        if (String.isBlank(forexType)) {
            return null;
        }
        for (Schema.PicklistEntry entry : Booking__c.FOREX_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == forexType) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String fullName(Contact c) {
        return ((c.FirstName == null ? '' : c.FirstName) + ' ' + c.LastName).trim();
    }

    private static String formatStartDate(Date d) {
        return d == null ? '' : d.day() + '/' + d.month() + '/' + (d.year() - 2000);
    }

    private static String truncate(String value, Integer maxLength) {
        return value.length() > maxLength ? value.left(maxLength) : value;
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    // ---------------------------------------------------------------------------------
    // Request DTOs (deserialized from the LWC)
    // ---------------------------------------------------------------------------------

    public class BookingRequest {
        public GuestInput primaryGuest;
        public List<GuestInput> paxGuests;
        public Id tourMasterId;
        public Id tourPlanId;
        public Decimal exchangeRate;
        public Boolean additionInTourCost;
        public Decimal inrAddition;
        public Decimal forexAddition;
        public Boolean reductionInTourCost;
        public Decimal inrReduction;
        public Decimal forexReduction;
        public Decimal standardDiscount;
        public Decimal specialDiscount;
        public List<Id> optionalTourIds;
        public String nomineeName;
        public String nomineeContactNumber;
        public String relationWithNominee;
        public String remarks;
    }

    public class GuestInput {
        public Id contactId;
        public NewContactInput newContact;
        public String roomType;
        public String mealPreference;
    }

    public class NewContactInput {
        public String salutation;
        public String firstName;
        public String lastName;
        public Date dateOfBirth;
        public String mobile;
        public String pan;
        public String passportNumber;
        public Date dateOfIssue;
        public Date dateOfExpiry;
    }
}