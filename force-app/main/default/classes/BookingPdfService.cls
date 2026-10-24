/**
 * Shared logic for the Booking PDFs (Booking Details / Tour Cost Calculation):
 * file naming, download headers and saving a generated PDF to the booking's Files.
 * Used by the bookingPdfViewer LWC and by the Visualforce page controllers.
 */
public with sharing class BookingPdfService {

    public static final String TYPE_BOOKING_DETAILS = 'bookingDetails';
    public static final String TYPE_TOUR_COST = 'tourCost';

    private static final Map<String, String> TITLES = new Map<String, String>{
        TYPE_BOOKING_DETAILS => 'Booking Details',
        TYPE_TOUR_COST => 'Tour Cost Calculation'
    };

    /**
     * Renders the requested PDF for the booking and attaches it to the booking's Files.
     * @return the ContentDocumentId of the new file
     */
    @AuraEnabled
    public static Id savePdf(Id bookingId, String pdfType) {
        if (bookingId == null || !TITLES.containsKey(pdfType)) {
            throw error('Invalid request: a booking and a PDF type are required.');
        }
        List<Booking__c> bookings = [SELECT Id, Name FROM Booking__c WHERE Id = :bookingId LIMIT 1];
        if (bookings.isEmpty()) {
            throw error('The booking was not found or you do not have access to it.');
        }

        PageReference page = pageFor(pdfType);
        page.getParameters().put('id', bookingId);
        Blob pdf;
        try {
            // getContent cannot run in tests
            pdf = Test.isRunningTest() ? Blob.valueOf('PDF') : page.getContent();
        } catch (Exception e) {
            throw error('The PDF could not be generated: ' + e.getMessage());
        }

        String title = TITLES.get(pdfType) + ' - ' + sanitize(bookings[0].Name)
            + ' (' + Datetime.now().format('dd-MM-yyyy HH.mm') + ')';
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = pdf,
            FirstPublishLocationId = bookingId
        );
        try {
            insert version;
        } catch (DmlException e) {
            throw error('The PDF could not be saved to Files: ' + e.getDmlMessage(0));
        }
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    /**
     * Called from the PDF page controllers. Names the file and, when the page is opened with
     * ?download=1, makes the browser download it instead of displaying it.
     */
    public static void applyResponseHeaders(String pdfType, String bookingName) {
        PageReference current = ApexPages.currentPage();
        if (current == null) {
            return;
        }
        String disposition = current.getParameters().get('download') == '1' ? 'attachment' : 'inline';
        current.getHeaders().put(
            'Content-Disposition',
            disposition + '; filename="' + fileName(pdfType, bookingName) + '"'
        );
    }

    public static String fileName(String pdfType, String bookingName) {
        String title = TITLES.containsKey(pdfType) ? TITLES.get(pdfType) : 'Booking';
        return title + ' - ' + sanitize(bookingName) + '.pdf';
    }

    private static PageReference pageFor(String pdfType) {
        return pdfType == TYPE_TOUR_COST ? Page.TourCostCalculationPage : Page.BookingPage;
    }

    private static String sanitize(String value) {
        return value == null ? '' : value.replaceAll('[\\\\/:*?"<>|]', '-');
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}