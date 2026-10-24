@IsTest
private class BookingPdfServiceTest {

    @TestSetup
    static void setup() {
        Tour_Master__c master = new Tour_Master__c(Name = 'Test Tour Master');
        insert master;
        Tour_Plan__c plan = new Tour_Plan__c(
            Name = 'TTP-Test', Tour_Master__c = master.Id, Cost_INR__c = 1000,
            Start_Date__c = Date.newInstance(2030, 3, 7), End_Date__c = Date.newInstance(2030, 3, 17)
        );
        insert plan;
        Contact c = new Contact(FirstName = 'Pdf', LastName = 'Guest');
        insert c;
        insert new Booking__c(Name = 'Pdf Guest-7/3/30', Contact__c = c.Id, Tour_Plan__c = plan.Id);
    }

    @IsTest
    static void savesBothPdfTypesToFiles() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        Id detailsDoc = BookingPdfService.savePdf(booking.Id, BookingPdfService.TYPE_BOOKING_DETAILS);
        Id costDoc = BookingPdfService.savePdf(booking.Id, BookingPdfService.TYPE_TOUR_COST);
        Test.stopTest();

        Assert.areNotEqual(null, detailsDoc);
        Assert.areNotEqual(null, costDoc);
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :booking.Id ORDER BY ContentDocument.Title
        ];
        Assert.areEqual(2, links.size());
        Assert.isTrue(links[0].ContentDocument.Title.startsWith('Booking Details - Pdf Guest-7-3-30'));
        Assert.isTrue(links[1].ContentDocument.Title.startsWith('Tour Cost Calculation - Pdf Guest-7-3-30'));
    }

    @IsTest
    static void rejectsInvalidInput() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        try {
            BookingPdfService.savePdf(booking.Id, 'unknown');
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid request'));
        }
        try {
            BookingPdfService.savePdf(null, BookingPdfService.TYPE_TOUR_COST);
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid request'));
        }
        delete booking;
        try {
            BookingPdfService.savePdf(booking.Id, BookingPdfService.TYPE_TOUR_COST);
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not found'));
        }
    }

    @IsTest
    static void namesFiles() {
        Assert.areEqual('Tour Cost Calculation - A-1-2-30.pdf', BookingPdfService.fileName(BookingPdfService.TYPE_TOUR_COST, 'A/1/2/30'));
        Assert.areEqual('Booking - .pdf', BookingPdfService.fileName('other', null));
    }

    @IsTest
    static void setsInlineOrDownloadHeaders() {
        // Outside a Visualforce request there is nothing to set
        BookingPdfService.applyResponseHeaders(BookingPdfService.TYPE_BOOKING_DETAILS, 'Any');

        PageReference page = Page.BookingPage;
        Test.setCurrentPage(page);
        BookingPdfService.applyResponseHeaders(BookingPdfService.TYPE_BOOKING_DETAILS, 'Guest-1/2/30');
        Assert.areEqual('inline; filename="Booking Details - Guest-1-2-30.pdf"', page.getHeaders().get('Content-Disposition'));

        page.getParameters().put('download', '1');
        BookingPdfService.applyResponseHeaders(BookingPdfService.TYPE_BOOKING_DETAILS, 'Guest-1/2/30');
        Assert.areEqual('attachment; filename="Booking Details - Guest-1-2-30.pdf"', page.getHeaders().get('Content-Disposition'));
    }
}