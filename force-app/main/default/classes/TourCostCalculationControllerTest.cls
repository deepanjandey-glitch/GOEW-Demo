@IsTest
private class TourCostCalculationControllerTest {

    /*
     * Worked example from the costing sheet (COSTING.pdf), exchange rate 117:
     *   INR part 160000 - discount 15000                     = sub total INR   145000
     *   Ground handling 1750 x 117                            = sub total GHC   204750
     *   Total package cost                                    =                 349750
     *   5% GST on total package cost                          =                  17487.50
     *   2% TCS on (package + GST) = 2% of 367237.50           =                   7344.75
     *   Total payable per head                                =                 374582.25
     *   Net cost after TCS refund                             =                 367237.50
     * Optional tours (45 + 115) x 117 = 18720, GST 936, TCS 2% of 19656 = 393.12, total 20049.12
     */
    @TestSetup
    static void setup() {
        Tour_Master__c master = new Tour_Master__c(Name = 'Iconic Switzerland', FOREX_Type__c = 'EURO');
        insert master;

        Tour_Plan__c plan = new Tour_Plan__c(
            Name = 'ICONIC SWITZERLAND - 22 MAY 2030',
            Tour_Master__c = master.Id,
            Cost_INR__c = 160000,
            Cost_in_Forex__c = 1750,
            Start_Date__c = Date.newInstance(2030, 5, 22),
            End_Date__c = Date.newInstance(2030, 5, 30),
            Single__c = 2400,
            Double_Tuwin_Triple__c = 1750,
            Child_With_Bed__c = 1200,
            Child_Without_Bed__c = 900,
            Predefined_Standard_Discount__c = 5000,
            Predefined_Special_Discount__c = 10000
        );
        insert plan;

        Contact primary = new Contact(FirstName = 'Primary', LastName = 'Guest');
        Contact pax = new Contact(FirstName = 'Single', LastName = 'Traveller');
        insert new List<Contact>{ primary, pax };

        Booking__c booking = new Booking__c(
            Name = 'Primary Guest-22/5/30',
            Contact__c = primary.Id,
            Tour_Plan__c = plan.Id,
            Booking_Status__c = 'Approved',
            Exchange_Rate__c = 117,
            INR_Component__c = 0,
            FOREX_Component__c = 0,
            INR_Component_Reduction__c = 0,
            FOREX_Component_Reduction__c = 0,
            Standard_Discount__c = 5000,
            Special_Discount__c = 10000,
            Optional_Tour__c = true,
            Optional_Tour_Cost__c = 160
        );
        insert booking;

        // The PAX is added first to prove the primary guest's sheet still comes first
        insert new Customer_Booking_List__c(Name = 'PAX', Booking__c = booking.Id, Customer__c = pax.Id, Room_Type__c = 'Single');
        insert new Customer_Booking_List__c(Name = 'Primary', Booking__c = booking.Id, Customer__c = primary.Id, Room_Type__c = 'Double');

        List<Optional_Tour__c> optionalTours = new List<Optional_Tour__c>{
            new Optional_Tour__c(Name = 'CHAPLIN\'S WORLD', Cost__c = 45, Tour_Master__c = master.Id),
            new Optional_Tour__c(Name = 'MOUNT RIGI', Cost__c = 115, Tour_Master__c = master.Id)
        };
        insert optionalTours;
        insert new List<Booking_Optional_Tour__c>{
            new Booking_Optional_Tour__c(Name = 'BOT-1', Booking__c = booking.Id, Optional_Tour__c = optionalTours[0].Id),
            new Booking_Optional_Tour__c(Name = 'BOT-2', Booking__c = booking.Id, Optional_Tour__c = optionalTours[1].Id)
        };
    }

    private static Booking__c booking() {
        return [SELECT Id FROM Booking__c LIMIT 1];
    }

    private static TourCostCalculationController controllerFor(Booking__c b) {
        return new TourCostCalculationController(new ApexPages.StandardController(b));
    }

    private static void assertAmount(Decimal expected, Decimal actual, String label) {
        Assert.isNotNull(actual, label + ' should be calculated');
        Assert.areEqual(expected.setScale(2), actual.setScale(2), label);
    }

    @IsTest
    static void matchesTheCostingSheet() {
        Test.startTest();
        TourCostCalculationController controller = controllerFor(booking());
        Test.stopTest();

        Assert.areEqual(5, controller.gstPercent);
        Assert.areEqual(2, controller.tcsPercent);
        Assert.areEqual('EURO', controller.forexType);
        Assert.isTrue(controller.hasExchangeRate);

        assertAmount(160000, controller.inrPart, 'INR part');
        assertAmount(15000, controller.discount, 'Discount');
        assertAmount(145000, controller.subTotalInr, 'Sub total INR');

        Assert.areEqual(2, controller.guests.size());
        TourCostCalculationController.GuestCost primary = controller.guests[0];
        Assert.areEqual('Primary Guest', primary.customerName, 'Primary guest sheet comes first');
        Assert.areEqual('Double', primary.roomType);
        Assert.isFalse(primary.isLast);
        Assert.isTrue(controller.guests[1].isLast);

        assertAmount(1750, primary.groundHandling, 'Ground handling charge');
        assertAmount(204750, primary.subTotalGhc, 'Sub total GHC');
        assertAmount(349750, primary.totalPackageCost, 'Total package cost');
        assertAmount(17487.50, primary.gst, '5% GST on total package cost');
        assertAmount(7344.75, primary.tcs, '2% TCS on total package cost incl. GST');
        assertAmount(374582.25, primary.totalPayable, 'Total payable per head');
        assertAmount(367237.50, primary.netCost, 'Net cost after TCS refund');
    }

    @IsTest
    static void costsTheSingleRoomGuestWithTheirOwnForex() {
        TourCostCalculationController.GuestCost single = controllerFor(booking()).guests[1];

        Assert.areEqual('Single Traveller', single.customerName);
        assertAmount(2400, single.groundHandling, 'Single room forex');
        assertAmount(280800, single.subTotalGhc, '2400 x 117');
        assertAmount(425800, single.totalPackageCost, '145000 + 280800');
        assertAmount(21290, single.gst, '5% GST');
        assertAmount(8941.80, single.tcs, '2% of 447090');
        assertAmount(456031.80, single.totalPayable, 'Total payable');
        assertAmount(447090, single.netCost, 'Net cost');
    }

    @IsTest
    static void costsOptionalToursSeparately() {
        TourCostCalculationController controller = controllerFor(booking());

        Assert.isTrue(controller.hasOptionalTours);
        Assert.areEqual(2, controller.optionalTours.size());
        Assert.areEqual('CHAPLIN\'S WORLD', controller.optionalTours[0].name);
        assertAmount(45, controller.optionalTours[0].forexCost, 'Chaplin\'s World (forex)');
        assertAmount(5265, controller.optionalTours[0].inrCost, 'Chaplin\'s World (INR)');
        assertAmount(13455, controller.optionalTours[1].inrCost, 'Mount Rigi (INR)');
        assertAmount(18720, controller.optionalSubTotal, 'Optional sub total');
        assertAmount(936, controller.optionalGst, '5% GST');
        assertAmount(393.12, controller.optionalTcs, '2% TCS');
        assertAmount(20049.12, controller.optionalTotal, 'Total optional cost in INR');

        // Optional tours are not part of the per-head package total
        assertAmount(374582.25, controller.guests[0].totalPayable, 'Package total excludes optional tours');
    }

    @IsTest
    static void formulaFieldsApplyTcsToTheWholePackage() {
        // The record formulas must agree with the PDF: package total + optional tours
        Customer_Booking_List__c cbl = [
            SELECT Total_INR__c, Total_FOREX_in_INR__c, Optional_Tour_Cost_in_INR__c, Total_Tour_Cost_in_INR__c
            FROM Customer_Booking_List__c WHERE Room_Type__c = 'Double'
        ];
        assertAmount(145000, cbl.Total_INR__c, 'Guest INR part');
        assertAmount(219287.25, cbl.Total_FOREX_in_INR__c, '204750 + 5% GST + 2% TCS');
        assertAmount(20049.12, cbl.Optional_Tour_Cost_in_INR__c, 'Optional tours with 5% GST + 2% TCS');
        assertAmount(374582.25 + 20049.12, cbl.Total_Tour_Cost_in_INR__c, 'Total tour cost = package total + optional tours');

        Booking__c b = [SELECT Total_Tour_Cost_in_INR__c FROM Booking__c LIMIT 1];
        assertAmount(374582.25 + 20049.12, b.Total_Tour_Cost_in_INR__c, 'Booking total tour cost');
    }

    @IsTest
    static void setsDownloadHeaders() {
        Booking__c b = booking();
        PageReference page = Page.TourCostCalculationPage;
        Test.setCurrentPage(page);

        controllerFor(b);
        String inline = page.getHeaders().get('Content-Disposition');
        page.getParameters().put('download', '1');
        controllerFor(b);
        String attachment = page.getHeaders().get('Content-Disposition');

        Assert.isTrue(inline.startsWith('inline;'), inline);
        Assert.isTrue(attachment.startsWith('attachment;'), attachment);
        Assert.isTrue(attachment.contains('Tour Cost Calculation - Primary Guest-22-5-30.pdf'), attachment);
    }

    @IsTest
    static void handlesMissingExchangeRate() {
        Booking__c b = booking();
        b.Exchange_Rate__c = null;
        update b;

        TourCostCalculationController controller = controllerFor(b);

        Assert.isFalse(controller.hasExchangeRate);
        assertAmount(0, controller.guests[0].subTotalGhc, 'No rate, no INR conversion');
        assertAmount(145000, controller.guests[0].totalPackageCost, 'INR part only');
        assertAmount(0, controller.optionalSubTotal, 'No rate, no optional INR cost');
    }

    @IsTest
    static void handlesBookingWithoutGuestsOrTourPlan() {
        Booking__c b = booking();
        delete [SELECT Id FROM Customer_Booking_List__c];
        delete [SELECT Id FROM Booking_Optional_Tour__c];
        b.Tour_Plan__c = null;
        update b;

        TourCostCalculationController controller = controllerFor(b);

        Assert.isNull(controller.BookingTourPlan);
        Assert.areEqual(0, controller.guests.size());
        Assert.isFalse(controller.hasOptionalTours);
    }

    @IsTest
    static void handlesMissingRecordId() {
        TourCostCalculationController controller = controllerFor(new Booking__c());
        Assert.isNull(controller.recordId);
        Assert.areEqual(0, controller.guests.size());
    }
}