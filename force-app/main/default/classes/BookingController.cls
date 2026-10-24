/**
 * Controller for BookingPage (the "Booking Details" PDF, laid out as the Guest Registration Form).
 */
public class BookingController {

    private static final Integer MIN_GUEST_ROWS = 5;
    private static final Integer MIN_OPTIONAL_ROWS = 3;

    public String recordId { get; private set; }
    public Booking__c Booking { get; private set; }
    public Contact BookingContact { get; private set; }
    public Tour_Plan__c BookingTourPlan { get; private set; }

    // Header details
    public String guestName { get; private set; }
    public String guestAddress { get; private set; }
    public String tourName { get; private set; }
    public String tourNumber { get; private set; }
    public String departureDate { get; private set; }
    public String ownerName { get; private set; }

    // Guests and costs
    public List<GuestRow> guests { get; private set; }
    public List<OptionalRow> optionalTours { get; private set; }
    public String forexType { get; private set; }
    public Decimal inrAmount { get; private set; }
    public Decimal forexAmount { get; private set; }
    public Decimal tipsAmount { get; private set; }

    public BookingController(ApexPages.StandardController stdController) {
        recordId = stdController.getId();
        guests = new List<GuestRow>();
        optionalTours = new List<OptionalRow>();
        if (recordId == null) {
            return;
        }
        loadBooking();
        loadGuests();
        loadOptionalTours();
        BookingPdfService.applyResponseHeaders(BookingPdfService.TYPE_BOOKING_DETAILS, Booking.Name);
    }

    private void loadBooking() {
        Booking = [
            SELECT Id, Name, Owner.Name, Contact__c, Booking_Status__c, Tips__c,
                   Total_INR__c, INR_Part__c, FOREX_Component__c, FOREX_Component_Reduction__c,
                   FOREX_Type__c, FOREX_Types_MT__c, Exchange_Rate__c,
                   Nominee_Name__c, Relation_with_Nominee__c, Nominee_Contact_Number__c,
                   Tour_Plan__c, Tour_Plan__r.Name, Tour_Plan__r.Start_Date__c, Tour_Plan__r.Cost_in_Forex__c,
                   Tour_Plan__r.Double_Tuwin_Triple__c, Tour_Plan__r.Tour_Master__r.Name
            FROM Booking__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        BookingTourPlan = Booking.Tour_Plan__r;
        ownerName = Booking.Owner.Name;

        if (Booking.Contact__c != null) {
            BookingContact = [
                SELECT Id, Name, Salutation, FirstName, LastName, Email, MobilePhone, Phone,
                       MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                       Emergency_Contact_Number__c
                FROM Contact
                WHERE Id = :Booking.Contact__c
                LIMIT 1
            ];
            guestName = joinNonBlank(new List<String>{ BookingContact.Salutation, BookingContact.FirstName, BookingContact.LastName }, ' ');
            guestAddress = joinNonBlank(new List<String>{
                BookingContact.MailingStreet, BookingContact.MailingCity, BookingContact.MailingState,
                BookingContact.MailingPostalCode, BookingContact.MailingCountry
            }, ', ');
        } else {
            BookingContact = new Contact();
        }

        if (BookingTourPlan != null) {
            tourName = BookingTourPlan.Tour_Master__r != null ? BookingTourPlan.Tour_Master__r.Name : null;
            tourNumber = BookingTourPlan.Name;
            departureDate = formatDate(BookingTourPlan.Start_Date__c);
        }

        forexType = String.isNotBlank(Booking.FOREX_Types_MT__c) ? Booking.FOREX_Types_MT__c : Booking.FOREX_Type__c;

        // Per person on twin/triple sharing basis
        inrAmount = Booking.Total_INR__c;
        Decimal twinForex = BookingTourPlan == null ? null
            : (nz(BookingTourPlan.Double_Tuwin_Triple__c) > 0 ? BookingTourPlan.Double_Tuwin_Triple__c : BookingTourPlan.Cost_in_Forex__c);
        if (twinForex != null || Booking.FOREX_Component__c != null) {
            // Reductions only apply once the booking is approved (as in Booking__c.Total_FOREX__c)
            Decimal reduction = Booking.Booking_Status__c == 'Approved' ? nz(Booking.FOREX_Component_Reduction__c) : 0;
            forexAmount = nz(twinForex) + nz(Booking.FOREX_Component__c) - reduction;
        }
        tipsAmount = Booking.Tips__c;
    }

    private void loadGuests() {
        List<Customer_Booking_List__c> lists = [
            SELECT Id, Customer__c, Meal_Preference__c, Room_Type__c,
                   Customer__r.FirstName, Customer__r.LastName, Customer__r.Date_Of_Birth__c,
                   Customer__r.Passport_Number__c, Customer__r.Date_Of_Issue__c, Customer__r.Date_Of_Expiry__c,
                   Customer__r.Nationality__c, Customer__r.MobilePhone,
                   Customer__r.Nominee_Name__c, Customer__r.Relation_with_Nominee__c
            FROM Customer_Booking_List__c
            WHERE Booking__c = :recordId AND Customer__c != null
            ORDER BY CreatedDate, Name
        ];

        // Primary guest first, the others in the order they were added
        List<Customer_Booking_List__c> ordered = new List<Customer_Booking_List__c>();
        for (Customer_Booking_List__c cbl : lists) {
            if (cbl.Customer__c == Booking.Contact__c) {
                ordered.add(cbl);
            }
        }
        for (Customer_Booking_List__c cbl : lists) {
            if (cbl.Customer__c != Booking.Contact__c) {
                ordered.add(cbl);
            }
        }

        for (Customer_Booking_List__c cbl : ordered) {
            GuestRow row = new GuestRow(guests.size() + 1);
            Contact c = cbl.Customer__r;
            row.firstName = c.FirstName;
            row.surname = c.LastName;
            row.dateOfBirth = formatDate(c.Date_Of_Birth__c);
            row.passportNumber = c.Passport_Number__c;
            row.dateOfIssue = formatDate(c.Date_Of_Issue__c);
            row.dateOfExpiry = formatDate(c.Date_Of_Expiry__c);
            row.nationality = c.Nationality__c;
            row.meal = cbl.Meal_Preference__c;
            row.roomType = cbl.Room_Type__c;
            row.mobile = c.MobilePhone;
            if (String.isNotBlank(c.Nominee_Name__c)) {
                row.nominee = c.Nominee_Name__c;
                row.relationship = c.Relation_with_Nominee__c;
            } else {
                row.nominee = Booking.Nominee_Name__c;
                row.relationship = Booking.Relation_with_Nominee__c;
                row.nomineeContact = Booking.Nominee_Contact_Number__c;
            }
            guests.add(row);
        }
        while (guests.size() < MIN_GUEST_ROWS) {
            guests.add(new GuestRow(guests.size() + 1));
        }
    }

    private void loadOptionalTours() {
        for (Booking_Optional_Tour__c bot : [
            SELECT Optional_Tour__r.Name, Optional_Tour__r.Cost__c
            FROM Booking_Optional_Tour__c
            WHERE Booking__c = :recordId AND Optional_Tour__c != null
            ORDER BY Name
        ]) {
            OptionalRow row = new OptionalRow();
            row.selected = true;
            row.name = bot.Optional_Tour__r.Name;
            row.currencyCode = forexType;
            row.amount = bot.Optional_Tour__r.Cost__c;
            optionalTours.add(row);
        }
        while (optionalTours.size() < MIN_OPTIONAL_ROWS) {
            OptionalRow blank = new OptionalRow();
            blank.selected = false;
            optionalTours.add(blank);
        }
    }

    private static String formatDate(Date d) {
        if (d == null) {
            return null;
        }
        return String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
    }

    private static String joinNonBlank(List<String> parts, String separator) {
        List<String> values = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                values.add(part.trim());
            }
        }
        return String.join(values, separator);
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    public class GuestRow {
        public Integer sl { get; private set; }
        public String firstName { get; set; }
        public String surname { get; set; }
        public String dateOfBirth { get; set; }
        public String passportNumber { get; set; }
        public String dateOfIssue { get; set; }
        public String dateOfExpiry { get; set; }
        public String nationality { get; set; }
        public String meal { get; set; }
        public String roomType { get; set; }
        public String mobile { get; set; }
        public String nominee { get; set; }
        public String relationship { get; set; }
        public String nomineeContact { get; set; }

        public GuestRow(Integer sl) {
            this.sl = sl;
        }
    }

    public class OptionalRow {
        public Boolean selected { get; set; }
        public String name { get; set; }
        public String currencyCode { get; set; }
        public Decimal amount { get; set; }
    }
}