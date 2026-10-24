/**
 * Controller for TourCostCalculationPage: the per-head package cost sheet, one page per guest.
 *
 * Package (per head)
 *   Sub total INR      = INR part - discount (standard + special + INR reduction)
 *   Sub total GHC      = ground handling charge (forex, by room type) x exchange rate
 *   Total package cost = sub total INR + sub total GHC
 *   GST                = 5% of the total package cost
 *   TCS                = 2% of (total package cost + GST)       -- refundable in ITR
 *   Total payable      = total package cost + GST + TCS
 *   Net cost           = total payable - TCS
 * Optional tours are costed separately in the same way (INR cost + 5% GST + 2% TCS).
 */
public class TourCostCalculationController {

    public static final Decimal GST_PERCENT = 5;
    public static final Decimal TCS_PERCENT = 2;

    public Decimal gstPercent { get { return GST_PERCENT; } }
    public Decimal tcsPercent { get { return TCS_PERCENT; } }

    public String recordId { get; private set; }
    public Booking__c Booking { get; private set; }
    public Tour_Plan__c BookingTourPlan { get; private set; }
    public String forexType { get; private set; }
    public Boolean hasExchangeRate { get; private set; }

    // INR part (same for every guest)
    public Decimal inrPart { get; private set; }
    public Decimal discount { get; private set; }
    public Decimal subTotalInr { get; private set; }

    // Optional tours (same for every guest)
    public List<OptionalLine> optionalTours { get; private set; }
    public Boolean hasOptionalTours { get { return optionalTours != null && !optionalTours.isEmpty(); } }
    public Decimal optionalSubTotal { get; private set; }
    public Decimal optionalGst { get; private set; }
    public Decimal optionalTcs { get; private set; }
    public Decimal optionalTotal { get; private set; }

    // One cost sheet per guest (the forex part depends on the room type)
    public List<GuestCost> guests { get; private set; }

    public TourCostCalculationController(ApexPages.StandardController stdController) {
        recordId = stdController.getId();
        guests = new List<GuestCost>();
        optionalTours = new List<OptionalLine>();
        if (recordId == null) {
            return;
        }

        Booking = [
            SELECT Id, Name, Contact__c, Exchange_Rate__c, FOREX_Type__c, FOREX_Types_MT__c, INR_Part__c,
                   Standard_Discount__c, Special_Discount__c, INR_Component_Reduction__c,
                   Tour_Plan__c, Tour_Plan__r.Name, Tour_Plan__r.Start_Date__c, Tour_Plan__r.Tour_Master__r.Name
            FROM Booking__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        BookingTourPlan = Booking.Tour_Plan__r;
        BookingPdfService.applyResponseHeaders(BookingPdfService.TYPE_TOUR_COST, Booking.Name);

        forexType = String.isNotBlank(Booking.FOREX_Types_MT__c) ? Booking.FOREX_Types_MT__c : Booking.FOREX_Type__c;
        hasExchangeRate = Booking.Exchange_Rate__c != null && Booking.Exchange_Rate__c > 0;
        Decimal rate = hasExchangeRate ? Booking.Exchange_Rate__c : 0;

        inrPart = nz(Booking.INR_Part__c);
        discount = nz(Booking.Standard_Discount__c) + nz(Booking.Special_Discount__c) + nz(Booking.INR_Component_Reduction__c);
        subTotalInr = inrPart - discount;

        loadOptionalTours(rate);

        // Primary guest first, then the others in the order they were added
        List<GuestCost> others = new List<GuestCost>();
        for (Customer_Booking_List__c cbl : [
            SELECT Id, Room_Type__c, Total_FOREX__c, Customer__c, Customer__r.Name
            FROM Customer_Booking_List__c
            WHERE Booking__c = :recordId
            ORDER BY CreatedDate, Name
        ]) {
            GuestCost guest = new GuestCost(cbl, subTotalInr, rate);
            if (cbl.Customer__c != null && cbl.Customer__c == Booking.Contact__c) {
                guests.add(guest);
            } else {
                others.add(guest);
            }
        }
        guests.addAll(others);
        if (!guests.isEmpty()) {
            guests[guests.size() - 1].isLast = true;
        }
    }

    private void loadOptionalTours(Decimal rate) {
        optionalSubTotal = 0;
        for (Booking_Optional_Tour__c bot : [
            SELECT Optional_Tour__r.Name, Optional_Tour__r.Cost__c
            FROM Booking_Optional_Tour__c
            WHERE Booking__c = :recordId AND Optional_Tour__c != null
            ORDER BY Name
        ]) {
            OptionalLine line = new OptionalLine();
            line.name = bot.Optional_Tour__r.Name;
            line.forexCost = nz(bot.Optional_Tour__r.Cost__c);
            line.inrCost = money(line.forexCost * rate);
            optionalTours.add(line);
            optionalSubTotal += line.inrCost;
        }
        optionalGst = money(optionalSubTotal * GST_PERCENT / 100);
        optionalTcs = money((optionalSubTotal + optionalGst) * TCS_PERCENT / 100);
        optionalTotal = optionalSubTotal + optionalGst + optionalTcs;
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Decimal money(Decimal value) {
        return value.setScale(2, RoundingMode.HALF_UP);
    }

    public class GuestCost {
        public String customerName { get; private set; }
        public String roomType { get; private set; }
        /** Drives the page break between guest sheets */
        public Boolean isLast { get; set; }

        public Decimal groundHandling { get; private set; }
        public Decimal subTotalGhc { get; private set; }
        public Decimal totalPackageCost { get; private set; }
        public Decimal gst { get; private set; }
        public Decimal tcs { get; private set; }
        public Decimal totalPayable { get; private set; }
        public Decimal netCost { get; private set; }

        public GuestCost(Customer_Booking_List__c cbl, Decimal subTotalInr, Decimal rate) {
            customerName = cbl.Customer__r != null ? cbl.Customer__r.Name : null;
            roomType = cbl.Room_Type__c;
            isLast = false;

            groundHandling = nz(cbl.Total_FOREX__c);
            subTotalGhc = money(groundHandling * rate);
            totalPackageCost = subTotalInr + subTotalGhc;
            gst = money(totalPackageCost * GST_PERCENT / 100);
            tcs = money((totalPackageCost + gst) * TCS_PERCENT / 100);
            totalPayable = totalPackageCost + gst + tcs;
            netCost = totalPayable - tcs;
        }
    }

    public class OptionalLine {
        public String name { get; private set; }
        public Decimal forexCost { get; private set; }
        public Decimal inrCost { get; private set; }
    }
}