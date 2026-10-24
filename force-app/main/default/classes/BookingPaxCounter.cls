/**
 * Keeps Booking__c.Total_PAX__c equal to the number of Customer Booking List records of each booking.
 * Customer_Booking_List__c.Booking__c is a lookup, so a roll-up summary field is not possible.
 * Runs without sharing so the count includes every guest, whoever can see them.
 */
public without sharing class BookingPaxCounter {

    /** Recounts the given bookings and updates the ones whose Total PAX changed. */
    public static void recount(Set<Id> bookingIds) {
        Set<Id> ids = new Set<Id>(bookingIds);
        ids.remove(null);
        if (ids.isEmpty()) {
            return;
        }

        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Booking__c bookingId, COUNT(Id) total
            FROM Customer_Booking_List__c
            WHERE Booking__c IN :ids
            GROUP BY Booking__c
        ]) {
            counts.put((Id) row.get('bookingId'), (Integer) row.get('total'));
        }

        List<Booking__c> changed = new List<Booking__c>();
        for (Booking__c booking : [SELECT Id, Total_PAX__c FROM Booking__c WHERE Id IN :ids]) {
            Integer total = counts.containsKey(booking.Id) ? counts.get(booking.Id) : 0;
            if (booking.Total_PAX__c != total) {
                changed.add(new Booking__c(Id = booking.Id, Total_PAX__c = total));
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        // A booking that fails its own validation rules (e.g. an old discount above the plan maximum)
        // must not block adding or removing guests, so failures are logged instead of thrown.
        for (Database.SaveResult result : Database.update(changed, false)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.WARN, 'Total PAX not updated for ' + result.getId() + ': ' + result.getErrors());
            }
        }
    }

    /** Booking ids affected by a Customer Booking List change (both old and new booking on a move). */
    public static Set<Id> affectedBookings(List<Customer_Booking_List__c> newRows, Map<Id, Customer_Booking_List__c> oldRows) {
        Set<Id> ids = new Set<Id>();
        if (newRows != null) {
            for (Customer_Booking_List__c row : newRows) {
                Customer_Booking_List__c old = oldRows == null ? null : oldRows.get(row.Id);
                if (old == null || old.Booking__c != row.Booking__c) {
                    ids.add(row.Booking__c);
                    if (old != null) {
                        ids.add(old.Booking__c);
                    }
                }
            }
        } else if (oldRows != null) {
            for (Customer_Booking_List__c old : oldRows.values()) {
                ids.add(old.Booking__c);
            }
        }
        return ids;
    }
}