@IsTest
private class BookingPaxCounterTest {

    @TestSetup
    static void setup() {
        Tour_Master__c master = new Tour_Master__c(Name = 'Pax Test Tour');
        insert master;
        Tour_Plan__c plan = new Tour_Plan__c(
            Name = 'PAX TOUR - 01 JAN 2030', Tour_Master__c = master.Id, Cost_INR__c = 1000,
            Start_Date__c = Date.newInstance(2030, 1, 1), End_Date__c = Date.newInstance(2030, 1, 10)
        );
        insert plan;
        insert new List<Contact>{
            new Contact(LastName = 'Guest One'),
            new Contact(LastName = 'Guest Two'),
            new Contact(LastName = 'Guest Three')
        };
        insert new List<Booking__c>{
            new Booking__c(Name = 'Booking A', Tour_Plan__c = plan.Id),
            new Booking__c(Name = 'Booking B', Tour_Plan__c = plan.Id)
        };
    }

    private static Map<String, Booking__c> bookings() {
        Map<String, Booking__c> byName = new Map<String, Booking__c>();
        for (Booking__c b : [SELECT Id, Name, Total_PAX__c FROM Booking__c]) {
            byName.put(b.Name, b);
        }
        return byName;
    }

    private static Decimal paxOf(String bookingName) {
        return bookings().get(bookingName).Total_PAX__c;
    }

    @IsTest
    static void countsGuestsThroughInsertDeleteUndeleteAndMove() {
        Id bookingA = bookings().get('Booking A').Id;
        Id bookingB = bookings().get('Booking B').Id;
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY LastName];

        Test.startTest();
        List<Customer_Booking_List__c> guests = new List<Customer_Booking_List__c>();
        for (Contact c : contacts) {
            guests.add(new Customer_Booking_List__c(Name = 'CBL', Booking__c = bookingA, Customer__c = c.Id));
        }
        insert guests;
        Assert.areEqual(3, paxOf('Booking A'), 'Three guests added');
        Assert.isNull(paxOf('Booking B'), 'Untouched booking is not recalculated');

        delete guests[0];
        Assert.areEqual(2, paxOf('Booking A'), 'One guest removed');

        undelete guests[0];
        Assert.areEqual(3, paxOf('Booking A'), 'Guest restored');

        // Moving a guest updates both bookings
        guests[1].Booking__c = bookingB;
        update guests[1];
        Assert.areEqual(2, paxOf('Booking A'));
        Assert.areEqual(1, paxOf('Booking B'));

        // An update that does not change the booking does not need a recount
        guests[2].Room_Type__c = 'Single';
        update guests[2];
        Assert.areEqual(2, paxOf('Booking A'));

        delete [SELECT Id FROM Customer_Booking_List__c WHERE Booking__c = :bookingA];
        Test.stopTest();

        Assert.areEqual(0, paxOf('Booking A'), 'No guests left');
    }

    @IsTest
    static void batchRepairsExistingBookings() {
        Id bookingA = bookings().get('Booking A').Id;
        insert new Customer_Booking_List__c(Name = 'CBL', Booking__c = bookingA, Customer__c = [SELECT Id FROM Contact LIMIT 1].Id);
        // Simulate data created before the automation existed
        update new List<Booking__c>{
            new Booking__c(Id = bookingA, Total_PAX__c = null),
            new Booking__c(Id = bookings().get('Booking B').Id, Total_PAX__c = 7)
        };

        Test.startTest();
        Database.executeBatch(new BookingPaxCountBatch(), 200);
        Test.stopTest();

        Assert.areEqual(1, paxOf('Booking A'));
        Assert.areEqual(0, paxOf('Booking B'));
    }

    @IsTest
    static void ignoresEmptyInput() {
        BookingPaxCounter.recount(new Set<Id>{ null });
        Assert.areEqual(0, BookingPaxCounter.affectedBookings(null, null).size());
    }
}