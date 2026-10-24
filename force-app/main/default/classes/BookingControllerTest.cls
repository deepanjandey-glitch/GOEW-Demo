@IsTest
private class BookingControllerTest {

    @TestSetup
    static void setup() {
        Tour_Master__c master = new Tour_Master__c(Name = 'Test Tour Master');
        insert master;

        Tour_Plan__c plan = new Tour_Plan__c(
            Name = 'TTP-Test',
            Tour_Master__c = master.Id,
            Cost_INR__c = 1000,
            Start_Date__c = Date.newInstance(2030, 3, 7),
            End_Date__c = Date.newInstance(2030, 3, 17),
            Single__c = 100,
            Double_Tuwin_Triple__c = 120,
            Child_With_Bed__c = 150,
            Child_Without_Bed__c = 200
        );
        insert plan;

        Contact primary = new Contact(
            Salutation = 'Mr.', FirstName = 'Primary', LastName = 'Guest', MobilePhone = '1223344556',
            Email = 'primary@example.com', MailingCity = 'Kolkata', Passport_Number__c = 'P1111111',
            Date_Of_Birth__c = Date.newInstance(1980, 1, 2)
        );
        Contact pax = new Contact(
            FirstName = 'Second', LastName = 'Traveller', MobilePhone = '9988776655',
            Nominee_Name__c = 'Own Nominee', Relation_with_Nominee__c = 'Sister'
        );
        insert new List<Contact>{ primary, pax };

        Booking__c booking = new Booking__c(
            Name = 'Primary Guest-7/3/30',
            Contact__c = primary.Id,
            Tour_Plan__c = plan.Id,
            Booking_Status__c = 'Approved',
            FOREX_Component__c = 10,
            FOREX_Component_Reduction__c = 5,
            INR_Component__c = 0,
            INR_Component_Reduction__c = 0,
            Standard_Discount__c = 0,
            Special_Discount__c = 0,
            Tips__c = 25,
            Nominee_Name__c = 'Booking Nominee',
            Relation_with_Nominee__c = 'Spouse',
            Nominee_Contact_Number__c = '9000000000'
        );
        insert booking;

        // PAX inserted first to prove the primary guest is still listed first
        insert new Customer_Booking_List__c(Name = 'CBL-PAX', Booking__c = booking.Id, Customer__c = pax.Id, Room_Type__c = 'Twin');
        insert new Customer_Booking_List__c(Name = 'CBL-Primary', Booking__c = booking.Id, Customer__c = primary.Id, Room_Type__c = 'Twin', Meal_Preference__c = 'Veg');

        Optional_Tour__c optionalTour = new Optional_Tour__c(Name = 'Boat Ride', Cost__c = 50, Tour_Master__c = master.Id);
        insert optionalTour;
        insert new Booking_Optional_Tour__c(Name = 'BOT', Booking__c = booking.Id, Optional_Tour__c = optionalTour.Id);
    }

    @IsTest
    static void buildsRegistrationFormData() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        PageReference page = Page.BookingPage;
        page.getParameters().put('download', '1');
        Test.setCurrentPage(page);
        BookingController controller = new BookingController(new ApexPages.StandardController(booking));
        Test.stopTest();

        Assert.areEqual(booking.Id, controller.recordId);
        Assert.areEqual('Mr. Primary Guest', controller.guestName);
        Assert.areEqual('Kolkata', controller.guestAddress);
        Assert.areEqual('Test Tour Master', controller.tourName);
        Assert.areEqual('TTP-Test', controller.tourNumber);
        Assert.areEqual('07/03/2030', controller.departureDate);

        // Primary first, padded to 5 rows
        Assert.areEqual(5, controller.guests.size());
        Assert.areEqual('Primary', controller.guests[0].firstName);
        Assert.areEqual('02/01/1980', controller.guests[0].dateOfBirth);
        Assert.areEqual('Veg', controller.guests[0].meal);
        Assert.areEqual('Booking Nominee', controller.guests[0].nominee);
        Assert.areEqual('9000000000', controller.guests[0].nomineeContact);
        Assert.areEqual('Second', controller.guests[1].firstName);
        Assert.areEqual('Own Nominee', controller.guests[1].nominee);
        Assert.isNull(controller.guests[2].firstName);

        // Twin/triple forex 120 + 10 addition - 5 reduction (approved)
        Assert.areEqual(125, controller.forexAmount);
        Assert.areEqual(25, controller.tipsAmount);

        Assert.areEqual(3, controller.optionalTours.size());
        Assert.isTrue(controller.optionalTours[0].selected);
        Assert.areEqual('Boat Ride', controller.optionalTours[0].name);
        Assert.isFalse(controller.optionalTours[1].selected);

        String disposition = page.getHeaders().get('Content-Disposition');
        Assert.isTrue(disposition.startsWith('attachment;'), disposition);
        Assert.isTrue(disposition.contains('Booking Details - Primary Guest-7-3-30.pdf'), disposition);
    }

    @IsTest
    static void handlesMissingRecordId() {
        BookingController controller = new BookingController(new ApexPages.StandardController(new Booking__c()));
        Assert.isNull(controller.recordId);
        Assert.areEqual(0, controller.guests.size());
    }

    @IsTest
    static void handlesBookingWithoutPrimaryContact() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        booking.Contact__c = null;
        update booking;

        BookingController controller = new BookingController(new ApexPages.StandardController(booking));

        Assert.isNull(controller.guestName);
        Assert.isNull(controller.BookingContact.Id);
        // Guests still come from the Customer Booking List, padded to 5 rows
        Assert.areEqual(5, controller.guests.size());
        Assert.isNotNull(controller.guests[0].firstName);
    }

    @IsTest
    static void appliesForexReductionOnlyWhenApproved() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        booking.Booking_Status__c = 'Send for approval';
        update booking;

        BookingController controller = new BookingController(new ApexPages.StandardController(booking));

        // Reduction is not applied until the booking is approved: 120 + 10
        Assert.areEqual(130, controller.forexAmount);
    }
}