/** Keeps Booking__c.Total_PAX__c in step with the booking's Customer Booking List records. */
trigger CustomerBookingListTrigger on Customer_Booking_List__c (after insert, after update, after delete, after undelete) {
    if (Trigger.isDelete) {
        BookingPaxCounter.recount(BookingPaxCounter.affectedBookings(null, Trigger.oldMap));
    } else {
        BookingPaxCounter.recount(BookingPaxCounter.affectedBookings(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null));
    }
}