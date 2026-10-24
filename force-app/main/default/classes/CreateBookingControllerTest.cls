@IsTest
private class CreateBookingControllerTest {

    @TestSetup
    static void setup() {
        Tour_Master__c master = new Tour_Master__c(Name = 'Test Europe Tour');
        insert master;

        insert new Tour_Plan__c(
            Name = 'TEST-Autumn',
            Tour_Master__c = master.Id,
            Season__c = 'Autumn',
            Start_Date__c = Date.newInstance(2030, 10, 17),
            End_Date__c = Date.newInstance(2030, 10, 27),
            Cost_INR__c = 300000,
            Cost_in_Forex__c = 2000,
            Single__c = 2500,
            Double_Tuwin_Triple__c = 2000,
            Predefined_Standard_Discount__c = 2000,
            Predefined_Special_Discount__c = 5000
        );

        insert new List<Optional_Tour__c>{
            new Optional_Tour__c(Name = 'Boat Ride', Cost__c = 50, Tour_Master__c = master.Id),
            new Optional_Tour__c(Name = 'Museum', Cost__c = 30, Tour_Master__c = master.Id)
        };

        insert new Contact(
            Salutation = 'Mr.', FirstName = 'Existing', LastName = 'Guest', MobilePhone = '9999999999',
            PAN_Number__c = 'ABCDE1234F', Passport_Number__c = 'P1234567',
            Date_Of_Issue__c = Date.newInstance(2020, 1, 1), Date_Of_Expiry__c = Date.newInstance(2030, 1, 1)
        );
    }

    private static Tour_Plan__c plan() {
        return [SELECT Id, Tour_Master__c FROM Tour_Plan__c LIMIT 1];
    }

    private static Contact existingContact() {
        return [SELECT Id FROM Contact WHERE LastName = 'Guest' LIMIT 1];
    }

    private static CreateBookingController.NewContactInput newContact(String passport, String pan) {
        CreateBookingController.NewContactInput c = new CreateBookingController.NewContactInput();
        c.salutation = 'Ms.';
        c.firstName = 'New';
        c.lastName = 'Traveller ' + passport;
        c.mobile = '8888888888';
        c.dateOfBirth = Date.newInstance(1985, 4, 12);
        c.pan = pan;
        c.passportNumber = passport;
        c.dateOfIssue = Date.newInstance(2022, 5, 1);
        c.dateOfExpiry = Date.newInstance(2032, 5, 1);
        return c;
    }

    private static CreateBookingController.GuestInput guest(Id contactId, CreateBookingController.NewContactInput n) {
        CreateBookingController.GuestInput g = new CreateBookingController.GuestInput();
        g.contactId = contactId;
        g.newContact = n;
        g.roomType = 'Double';
        g.mealPreference = 'Veg';
        return g;
    }

    private static CreateBookingController.BookingRequest baseRequest(CreateBookingController.GuestInput primary) {
        Tour_Plan__c p = plan();
        CreateBookingController.BookingRequest req = new CreateBookingController.BookingRequest();
        req.primaryGuest = primary;
        req.paxGuests = new List<CreateBookingController.GuestInput>();
        req.tourMasterId = p.Tour_Master__c;
        req.tourPlanId = p.Id;
        req.exchangeRate = 85.50;
        req.nomineeName = 'Test Nominee';
        req.relationWithNominee = 'Spouse';
        req.standardDiscount = 1000;
        req.specialDiscount = 0;
        return req;
    }

    private static String expectError(CreateBookingController.BookingRequest req) {
        try {
            CreateBookingController.createBooking(JSON.serialize(req));
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        Assert.fail('Expected an AuraHandledException');
        return null;
    }

    @IsTest
    static void lookupsReturnData() {
        Tour_Plan__c p = plan();
        Test.startTest();
        List<Contact> found = CreateBookingController.searchContacts('Exist', null);
        List<Contact> excluded = CreateBookingController.searchContacts('Exist', new List<Id>{ found[0].Id });
        List<Contact> tooShort = CreateBookingController.searchContacts('E', null);
        List<Contact> byPan = CreateBookingController.searchContacts('ABCDE1234F', null);
        List<Tour_Master__c> masters = CreateBookingController.getTourMasters();
        List<Tour_Plan__c> plans = CreateBookingController.getTourPlans(p.Tour_Master__c);
        List<Optional_Tour__c> optionals = CreateBookingController.getOptionalTours(p.Tour_Master__c);
        Test.stopTest();

        Assert.areEqual(1, found.size());
        Assert.areEqual(0, excluded.size());
        Assert.areEqual(0, tooShort.size());
        Assert.areEqual(0, byPan.size(), 'PAN is not a search field');
        Assert.areEqual(1, masters.size());
        Assert.areEqual(1, plans.size());
        Assert.areEqual(2, optionals.size());
        Assert.areEqual(0, CreateBookingController.getTourPlans(null).size());
        Assert.areEqual(0, CreateBookingController.getOptionalTours(null).size());
    }

    @IsTest
    static void lookupsFailGracefullyWithoutAccess() {
        Tour_Plan__c p = plan();
        Profile minimal = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User restricted = new User(
            ProfileId = minimal.Id,
            LastName = 'Restricted',
            Alias = 'restr',
            Email = 'restricted' + unique + '@example.com',
            Username = 'restricted' + unique + '@createbooking.test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata'
        );
        insert restricted;

        Integer failures = 0;
        Test.startTest();
        System.runAs(restricted) {
            try {
                CreateBookingController.searchContacts('Exist', null);
            } catch (AuraHandledException e) {
                failures++;
                Assert.isTrue(e.getMessage().contains('Contacts could not be searched'));
            }
            try {
                CreateBookingController.getTourMasters();
            } catch (AuraHandledException e) {
                failures++;
                Assert.isTrue(e.getMessage().contains('Tour Masters could not be loaded'));
            }
            try {
                CreateBookingController.getTourPlans(p.Tour_Master__c);
            } catch (AuraHandledException e) {
                failures++;
                Assert.isTrue(e.getMessage().contains('Tour Plans could not be loaded'));
            }
            try {
                CreateBookingController.getOptionalTours(p.Tour_Master__c);
            } catch (AuraHandledException e) {
                failures++;
                Assert.isTrue(e.getMessage().contains('Optional Tours could not be loaded'));
            }
        }
        Test.stopTest();

        Assert.areEqual(4, failures, 'A user without object access must get a readable error from every lookup');
    }

    @IsTest
    static void createsApprovedBookingWithExistingAndNewGuests() {
        CreateBookingController.BookingRequest req = baseRequest(guest(existingContact().Id, null));
        // PAX are created without Mobile and PAN
        CreateBookingController.NewContactInput paxContact = newContact('N1234567', null);
        paxContact.mobile = null;
        req.paxGuests.add(guest(null, paxContact));
        req.additionInTourCost = true;
        req.inrAddition = 5000;
        req.forexAddition = 100;
        req.optionalTourIds = new List<Id>();
        for (Optional_Tour__c ot : [SELECT Id FROM Optional_Tour__c]) {
            req.optionalTourIds.add(ot.Id);
        }

        Test.startTest();
        Id bookingId = CreateBookingController.createBooking(JSON.serialize(req));
        Test.stopTest();

        Booking__c b = [
            SELECT Name, Booking_Status__c, Contact__c, INR_Component__c, FOREX_Component__c, Exchange_Rate__c,
                   Standard_Discount__c, Optional_Tour__c, Optional_Tour_Cost__c
            FROM Booking__c WHERE Id = :bookingId
        ];
        Assert.areEqual('Existing Guest-17/10/30', b.Name);
        Assert.areEqual(85.50, b.Exchange_Rate__c);
        Assert.areEqual('Approved', b.Booking_Status__c);
        Assert.areEqual(existingContact().Id, b.Contact__c);
        Assert.areEqual(5000, b.INR_Component__c);
        Assert.areEqual(100, b.FOREX_Component__c);
        Assert.areEqual(1000, b.Standard_Discount__c);
        Assert.isTrue(b.Optional_Tour__c);
        Assert.areEqual(80, b.Optional_Tour_Cost__c);

        Assert.areEqual(2, [SELECT COUNT() FROM Customer_Booking_List__c WHERE Booking__c = :bookingId]);
        Assert.areEqual(2, [SELECT COUNT() FROM Booking_Optional_Tour__c WHERE Booking__c = :bookingId]);
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Passport_Number__c = 'N1234567' AND MobilePhone = null AND Date_Of_Birth__c = 1985-04-12]);
        // Total PAX is maintained by the Customer Booking List trigger
        Assert.areEqual(2, [SELECT Total_PAX__c FROM Booking__c WHERE Id = :bookingId].Total_PAX__c);
    }

    @IsTest
    static void reductionSendsForApprovalWithNewPrimaryGuest() {
        CreateBookingController.BookingRequest req = baseRequest(guest(null, newContact('R1234567', 'ABCDE1234F')));
        req.reductionInTourCost = true;
        req.inrReduction = 2000;

        Test.startTest();
        Id bookingId = CreateBookingController.createBooking(JSON.serialize(req));
        Test.stopTest();

        Booking__c b = [SELECT Name, Booking_Status__c, INR_Component_Reduction__c FROM Booking__c WHERE Id = :bookingId];
        Assert.areEqual('Send for approval', b.Booking_Status__c);
        Assert.areEqual(2000, b.INR_Component_Reduction__c);
        Assert.isTrue(b.Name.startsWith('New Traveller R1234567-'));
    }

    @IsTest
    static void rejectsInvalidRequests() {
        Id existingId = existingContact().Id;

        // Discount above the predefined maximum
        CreateBookingController.BookingRequest req = baseRequest(guest(existingId, null));
        req.standardDiscount = 2500;
        Assert.isTrue(expectError(req).contains('Standard Discount'));

        // Primary guest PAN missing
        req = baseRequest(guest(null, newContact('X1234567', null)));
        Assert.isTrue(expectError(req).contains('PAN'));

        // Primary guest Mobile missing
        CreateBookingController.NewContactInput noMobile = newContact('M1234567', 'ABCDE1234F');
        noMobile.mobile = null;
        req = baseRequest(guest(null, noMobile));
        Assert.isTrue(expectError(req).contains('Mobile'));

        // Date of Birth is mandatory for every new contact (primary and PAX) and cannot be in the future
        CreateBookingController.NewContactInput noDob = newContact('B1234567', null);
        noDob.dateOfBirth = null;
        req = baseRequest(guest(existingId, null));
        req.paxGuests.add(guest(null, noDob));
        Assert.isTrue(expectError(req).contains('Date of Birth'));
        CreateBookingController.NewContactInput futureDob = newContact('B7654321', 'ABCDE1234F');
        futureDob.dateOfBirth = Date.today().addDays(1);
        req = baseRequest(guest(null, futureDob));
        Assert.isTrue(expectError(req).contains('Date of Birth cannot be in the future'));

        // Invalid PAN format
        req = baseRequest(guest(null, newContact('X1234567', 'ABC123')));
        Assert.isTrue(expectError(req).contains('PAN'));

        // Passport already on an existing contact
        req = baseRequest(guest(null, newContact('P1234567', 'ABCDE1234F')));
        Assert.isTrue(expectError(req).contains('already exists'));

        // Same contact twice
        req = baseRequest(guest(existingId, null));
        req.paxGuests.add(guest(existingId, null));
        Assert.isTrue(expectError(req).contains('more than once'));

        // Addition checked without any amount
        req = baseRequest(guest(existingId, null));
        req.additionInTourCost = true;
        Assert.isTrue(expectError(req).contains('Addition in Tour Cost'));

        // Missing room type
        CreateBookingController.GuestInput g = guest(existingId, null);
        g.roomType = null;
        req = baseRequest(g);
        Assert.isTrue(expectError(req).contains('Room Type'));

        // Missing primary guest
        req = baseRequest(null);
        Assert.isTrue(expectError(req).contains('Primary Guest'));

        // Missing tour plan
        req = baseRequest(guest(existingId, null));
        req.tourPlanId = null;
        Assert.isTrue(expectError(req).contains('Tour Plan'));

        // Expiry before issue
        CreateBookingController.NewContactInput n = newContact('Y1234567', 'ABCDE1234F');
        n.dateOfExpiry = n.dateOfIssue.addDays(-1);
        req = baseRequest(guest(null, n));
        Assert.isTrue(expectError(req).contains('Date of Expiry'));

        // Nominee details are mandatory
        req = baseRequest(guest(existingId, null));
        req.nomineeName = ' ';
        Assert.isTrue(expectError(req).contains('Nominee Name'));
        req = baseRequest(guest(existingId, null));
        req.relationWithNominee = null;
        Assert.isTrue(expectError(req).contains('Relation with Nominee'));

        // Non-positive exchange rate
        req = baseRequest(guest(existingId, null));
        req.exchangeRate = 0;
        Assert.isTrue(expectError(req).contains('Exchange Rate'));

        // Unreadable payload
        try {
            CreateBookingController.createBooking('not json');
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('could not be read'));
        }

        Assert.areEqual(0, [SELECT COUNT() FROM Booking__c]);
    }

    @IsTest
    static void blocksDuplicateBooking() {
        CreateBookingController.BookingRequest req = baseRequest(guest(existingContact().Id, null));
        CreateBookingController.createBooking(JSON.serialize(req));

        Test.startTest();
        String message = expectError(req);
        Test.stopTest();

        Assert.isTrue(message.contains('already exists'));
        Assert.areEqual(1, [SELECT COUNT() FROM Booking__c]);
    }

    @IsTest
    static void copiesForexTypeFromTourMaster() {
        Tour_Master__c master = [SELECT Id FROM Tour_Master__c LIMIT 1];
        master.FOREX_Type__c = 'USD';
        update master;

        Id bookingId = CreateBookingController.createBooking(JSON.serialize(baseRequest(guest(existingContact().Id, null))));

        Assert.areEqual('USD', [SELECT FOREX_Type__c FROM Booking__c WHERE Id = :bookingId].FOREX_Type__c);
    }

    @IsTest
    static void rollsBackEverythingWhenASaveFails() {
        // Contacts and the booking are inserted before the guest list; an invalid (restricted)
        // meal preference makes that last insert fail, which must undo the earlier inserts too.
        CreateBookingController.GuestInput primary = guest(null, newContact('F1234567', 'ABCDE1234F'));
        primary.mealPreference = 'Not A Meal';
        CreateBookingController.BookingRequest req = baseRequest(primary);

        Test.startTest();
        String message = expectError(req);
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(message));
        Assert.areEqual(0, [SELECT COUNT() FROM Booking__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM Customer_Booking_List__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Passport_Number__c = 'F1234567']);
    }

    @IsTest
    static void rejectsInconsistentRequests() {
        Id existingId = existingContact().Id;
        CreateBookingController.BookingRequest req;

        // Empty payload
        try {
            CreateBookingController.createBooking('null');
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('empty'));
        }

        // PAX slot left empty
        req = baseRequest(guest(existingId, null));
        req.paxGuests.add(guest(null, null));
        Assert.isTrue(expectError(req).contains('PAX 1'));

        // Same passport entered for two new contacts
        req = baseRequest(guest(null, newContact('D1234567', 'ABCDE1234F')));
        req.paxGuests.add(guest(null, newContact('D1234567', null)));
        Assert.isTrue(expectError(req).contains('more than one new contact'));

        // Passport longer than the field allows
        req = baseRequest(guest(null, newContact('P12345678901', 'ABCDE1234F')));
        Assert.isTrue(expectError(req).contains('valid Passport Number'));

        // Tour plan from another tour master
        Tour_Master__c otherMaster = new Tour_Master__c(Name = 'Other Tour');
        insert otherMaster;
        req = baseRequest(guest(existingId, null));
        req.tourMasterId = otherMaster.Id;
        Assert.isTrue(expectError(req).contains('does not belong'));

        // Optional tour from another tour master
        Optional_Tour__c otherTour = new Optional_Tour__c(Name = 'Elsewhere', Cost__c = 10, Tour_Master__c = otherMaster.Id);
        insert otherTour;
        req = baseRequest(guest(existingId, null));
        req.optionalTourIds = new List<Id>{ otherTour.Id };
        Assert.isTrue(expectError(req).contains('Optional Tours'));

        // Negative adjustment component
        req = baseRequest(guest(existingId, null));
        req.additionInTourCost = true;
        req.inrAddition = -5;
        req.forexAddition = 10;
        Assert.isTrue(expectError(req).contains('cannot be negative'));

        // Reduction checked without any amount
        req = baseRequest(guest(existingId, null));
        req.reductionInTourCost = true;
        Assert.isTrue(expectError(req).contains('Reduction in Tour Cost'));

        // Tour plan deleted after it was selected
        Tour_Plan__c doomed = new Tour_Plan__c(
            Name = 'Doomed', Tour_Master__c = otherMaster.Id, Cost_INR__c = 1,
            Start_Date__c = Date.newInstance(2030, 1, 1), End_Date__c = Date.newInstance(2030, 1, 2)
        );
        insert doomed;
        delete doomed;
        req = baseRequest(guest(existingId, null));
        req.tourMasterId = null;
        req.tourPlanId = doomed.Id;
        Assert.isTrue(expectError(req).contains('no longer exists'));

        Assert.areEqual(0, [SELECT COUNT() FROM Booking__c]);
    }

    @IsTest
    static void rejectsDeletedContact() {
        Contact gone = new Contact(LastName = 'Gone', Passport_Number__c = 'G1234567');
        insert gone;
        delete gone;

        String message = expectError(baseRequest(guest(gone.Id, null)));

        Assert.isTrue(message.contains('no longer exists'), message);
        Assert.areEqual(0, [SELECT COUNT() FROM Booking__c]);
    }

    @IsTest
    static void listsLatestTourPlansFirst() {
        Tour_Plan__c existing = plan();
        insert new Tour_Plan__c(
            Name = 'TEST - 05 JUNE 2031', Tour_Master__c = existing.Tour_Master__c, Cost_INR__c = 1,
            Start_Date__c = Date.newInstance(2031, 6, 5), End_Date__c = Date.newInstance(2031, 6, 15)
        );

        List<Tour_Plan__c> plans = CreateBookingController.getTourPlans(existing.Tour_Master__c);

        Assert.areEqual(2, plans.size());
        Assert.areEqual('TEST - 05 JUNE 2031', plans[0].Name, 'Latest departure first');
        Assert.areEqual('TEST-Autumn', plans[1].Name);
    }
}
