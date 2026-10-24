/**
 * One-off / repair job: recalculates Booking__c.Total_PAX__c for every booking.
 * Run from Anonymous Apex:  Database.executeBatch(new BookingPaxCountBatch(), 200);
 */
public without sharing class BookingPaxCountBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([SELECT Id FROM Booking__c]);
    }

    public void execute(Database.BatchableContext context, List<Booking__c> scope) {
        BookingPaxCounter.recount(new Map<Id, Booking__c>(scope).keySet());
    }

    public void finish(Database.BatchableContext context) {
    }
}