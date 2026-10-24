import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CUSTOMER_BOOKING_LIST_OBJECT from '@salesforce/schema/Customer_Booking_List__c';
import ROOM_TYPE_FIELD from '@salesforce/schema/Customer_Booking_List__c.Room_Type__c';
import MEAL_PREFERENCE_FIELD from '@salesforce/schema/Customer_Booking_List__c.Meal_Preference__c';
import getTourMasters from '@salesforce/apex/CreateBookingController.getTourMasters';
import getTourPlans from '@salesforce/apex/CreateBookingController.getTourPlans';
import getOptionalTours from '@salesforce/apex/CreateBookingController.getOptionalTours';
import createBooking from '@salesforce/apex/CreateBookingController.createBooking';
import NewContactModal from 'c/newContactModal';

const MAX_PAX = 20;
// When a toggle is on, at least one of its two components must be filled
const ADJUSTMENTS = [
    { toggle: 'additionInTourCost', fields: ['inrAddition', 'forexAddition'], label: 'Addition in Tour Cost' },
    { toggle: 'reductionInTourCost', fields: ['inrReduction', 'forexReduction'], label: 'Reduction in Tour Cost' }
];
const DAY_MS = 24 * 60 * 60 * 1000;

export default class CreateBooking extends NavigationMixin(LightningElement) {
    // Guests
    primaryGuest = null;
    primaryRoomType;
    primaryMealPreference;
    paxCount = 0;
    paxRows = [];

    // Tour
    tourMasterId;
    tourPlanId;
    tourMasters = [];
    tourPlans = [];
    optionalTours = [];
    isLoadingPlans = false;
    exchangeRate;

    // Tour cost adjustments
    additionInTourCost = false;
    inrAddition;
    forexAddition;
    reductionInTourCost = false;
    inrReduction;
    forexReduction;

    // Discounts
    standardDiscount;
    specialDiscount;

    // Optional tours, nominee, misc
    includeOptionalTours = false;
    selectedOptionalTourIds = [];
    nomineeName;
    nomineeContactNumber;
    relationWithNominee;
    remarks;

    roomTypeOptions = [];
    mealPreferenceOptions = [];
    isSaving = false;
    keySeq = 0;

    // ---------------------------------------------------------------------------------
    // Wires
    // ---------------------------------------------------------------------------------

    @wire(getObjectInfo, { objectApiName: CUSTOMER_BOOKING_LIST_OBJECT })
    bookingListInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$bookingListInfo.data.defaultRecordTypeId',
        fieldApiName: ROOM_TYPE_FIELD
    })
    wiredRoomTypes({ data, error }) {
        if (data) {
            this.roomTypeOptions = toOptions(data.values);
        } else if (error) {
            this.showError('Could not load Room Types', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$bookingListInfo.data.defaultRecordTypeId',
        fieldApiName: MEAL_PREFERENCE_FIELD
    })
    wiredMealPreferences({ data, error }) {
        if (data) {
            this.mealPreferenceOptions = toOptions(data.values);
        } else if (error) {
            this.showError('Could not load Meal Preferences', error);
        }
    }

    @wire(getTourMasters)
    wiredTourMasters({ data, error }) {
        if (data) {
            this.tourMasters = data;
        } else if (error) {
            this.showError('Could not load Tour Masters', error);
        }
    }

    @wire(getTourPlans, { tourMasterId: '$tourMasterId' })
    wiredTourPlans({ data, error }) {
        if (data) {
            this.tourPlans = data;
            this.isLoadingPlans = false;
        } else if (error) {
            this.isLoadingPlans = false;
            this.showError('Could not load Tour Plans', error);
        }
    }

    @wire(getOptionalTours, { tourMasterId: '$tourMasterId' })
    wiredOptionalTours({ data, error }) {
        if (data) {
            this.optionalTours = data;
        } else if (error) {
            this.showError('Could not load Optional Tours', error);
        }
    }

    // ---------------------------------------------------------------------------------
    // Guests
    // ---------------------------------------------------------------------------------

    get selectedContactIds() {
        return [this.primaryGuest, ...this.paxRows.map((r) => r.guest)]
            .filter((g) => g && g.contactId)
            .map((g) => g.contactId);
    }

    get hasPaxRows() {
        return this.paxRows.length > 0;
    }

    get maxPax() {
        return MAX_PAX;
    }

    get travellerCount() {
        return 1 + this.paxRows.length;
    }

    get travellerCountLabel() {
        return this.travellerCount === 1 ? '1 traveller' : `${this.travellerCount} travellers`;
    }

    get primaryGuestName() {
        return this.primaryGuest ? this.primaryGuest.name : 'Not selected';
    }

    get guestsComplete() {
        return !!this.primaryGuest && !!this.primaryRoomType && this.paxRows.every((r) => r.guest && r.roomType);
    }

    // ---------------------------------------------------------------------------------
    // Tour
    // ---------------------------------------------------------------------------------

    get tourMasterOptions() {
        return this.tourMasters.map((m) => ({ label: m.Name, value: m.Id }));
    }

    get tourPlanOptions() {
        // Plan names already carry the departure date (e.g. "SPARKLE OF EUROPE - 09 JULY 2027"); the picker bolds it
        return this.tourPlans.map((p) => ({ label: p.Name, value: p.Id }));
    }

    get isTourPlanDisabled() {
        return !this.tourMasterId || this.isLoadingPlans;
    }

    get tourPlanPlaceholder() {
        if (!this.tourMasterId) {
            return 'Select a Tour Master first';
        }
        if (!this.isLoadingPlans && this.tourPlans.length === 0) {
            return 'No Tour Plans for this Tour Master';
        }
        return 'Select a Tour Plan';
    }

    get selectedTourMaster() {
        return this.tourMasters.find((m) => m.Id === this.tourMasterId);
    }

    get selectedTourPlan() {
        return this.tourPlans.find((p) => p.Id === this.tourPlanId);
    }

    get forexType() {
        const plan = this.selectedTourPlan;
        const master = this.selectedTourMaster;
        return (plan && plan.FOREX_Type__c) || (master && master.FOREX_Type__c) || '';
    }

    get forexLabel() {
        return this.forexType || 'Forex';
    }

    get hasForexType() {
        return !!this.forexType;
    }

    get exchangeRateLabel() {
        return `Exchange Rate (INR per 1 ${this.forexLabel})`;
    }

    get forexAdditionLabel() {
        return `Forex Component (${this.forexLabel})`;
    }

    get forexReductionLabel() {
        return `Forex Component (${this.forexLabel})`;
    }

    get planStartDate() {
        return formatDate(this.selectedTourPlan && this.selectedTourPlan.Start_Date__c);
    }

    get planEndDate() {
        return formatDate(this.selectedTourPlan && this.selectedTourPlan.End_Date__c);
    }

    get planDuration() {
        const plan = this.selectedTourPlan;
        if (!plan || !plan.Start_Date__c || !plan.End_Date__c) {
            return '';
        }
        const nights = Math.round((Date.parse(plan.End_Date__c) - Date.parse(plan.Start_Date__c)) / DAY_MS);
        return `${nights + 1}D / ${nights}N`;
    }

    get planTwinForex() {
        return this.selectedTourPlan ? num(this.selectedTourPlan.Double_Tuwin_Triple__c) : 0;
    }

    get planSingleForex() {
        return this.selectedTourPlan ? num(this.selectedTourPlan.Single__c) : 0;
    }

    get tourSummaryLabel() {
        const plan = this.selectedTourPlan;
        const master = this.selectedTourMaster;
        if (!master) {
            return 'Not selected';
        }
        return plan ? `${master.Name} · ${plan.Name}` : master.Name;
    }

    // ---------------------------------------------------------------------------------
    // Discounts
    // ---------------------------------------------------------------------------------

    get standardDiscountMax() {
        return (this.selectedTourPlan && this.selectedTourPlan.Predefined_Standard_Discount__c) || 0;
    }

    get specialDiscountMax() {
        return (this.selectedTourPlan && this.selectedTourPlan.Predefined_Special_Discount__c) || 0;
    }

    get isStandardDiscountDisabled() {
        return this.standardDiscountMax <= 0;
    }

    get isSpecialDiscountDisabled() {
        return this.specialDiscountMax <= 0;
    }

    get standardDiscountRangeMessage() {
        return `Standard Discount cannot exceed the maximum available value of ${formatInr(this.standardDiscountMax)}.`;
    }

    get specialDiscountRangeMessage() {
        return `Special Discount cannot exceed the maximum available value of ${formatInr(this.specialDiscountMax)}.`;
    }

    // ---------------------------------------------------------------------------------
    // Optional tours
    // ---------------------------------------------------------------------------------

    get hasOptionalTours() {
        return this.optionalTours.length > 0;
    }

    get optionalTourOptions() {
        return this.optionalTours.map((t) => ({
            label: t.Cost__c != null ? `${t.Name} — ${t.Cost__c} ${this.forexLabel}` : t.Name,
            value: t.Id
        }));
    }

    get selectedOptionalTours() {
        if (!this.includeOptionalTours) {
            return [];
        }
        return this.optionalTours.filter((t) => this.selectedOptionalTourIds.includes(t.Id));
    }

    get optionalTourForex() {
        return this.selectedOptionalTours.reduce((sum, t) => sum + num(t.Cost__c), 0);
    }

    get hasSelectedOptionalTours() {
        return this.selectedOptionalTours.length > 0;
    }

    // ---------------------------------------------------------------------------------
    // Summary (per person, twin/triple sharing)
    // ---------------------------------------------------------------------------------

    get inrBase() {
        return this.selectedTourPlan ? num(this.selectedTourPlan.Cost_INR__c) : 0;
    }

    get inrAdditionValue() {
        return this.additionInTourCost ? num(this.inrAddition) : 0;
    }

    get inrReductionValue() {
        return this.reductionInTourCost ? num(this.inrReduction) : 0;
    }

    get totalDiscount() {
        return num(this.standardDiscount) + num(this.specialDiscount);
    }

    get hasInrAddition() {
        return this.inrAdditionValue > 0;
    }

    get hasInrReduction() {
        return this.inrReductionValue > 0;
    }

    get hasDiscount() {
        return this.totalDiscount > 0;
    }

    /** Same arithmetic as Booking__c.Total_INR__c for an approved booking */
    get netInr() {
        return this.inrBase + this.inrAdditionValue - this.inrReductionValue - this.totalDiscount;
    }

    get netForex() {
        return (
            this.planTwinForex +
            (this.additionInTourCost ? num(this.forexAddition) : 0) -
            (this.reductionInTourCost ? num(this.forexReduction) : 0)
        );
    }

    get hasExchangeRate() {
        return num(this.exchangeRate) > 0;
    }

    get forexInInr() {
        return this.netForex * num(this.exchangeRate);
    }

    get bookingStatus() {
        return this.reductionInTourCost ? 'Send for approval' : 'Approved';
    }

    get statusBadgeClass() {
        return this.reductionInTourCost ? 'cb-status cb-status_pending' : 'cb-status cb-status_ok';
    }

    get statusIcon() {
        return this.reductionInTourCost ? 'utility:clock' : 'utility:success';
    }

    // ---------------------------------------------------------------------------------
    // Primary guest handlers
    // ---------------------------------------------------------------------------------

    handlePrimarySelect(event) {
        this.primaryGuest = event.detail;
    }

    handlePrimaryRemove() {
        this.primaryGuest = null;
    }

    async handlePrimaryNewContact(event) {
        const guest = await this.openNewContact('New Primary Guest', true, event.detail.searchTerm);
        if (guest) {
            this.primaryGuest = guest;
        }
    }

    handlePrimaryRoomType(event) {
        this.primaryRoomType = event.detail.value;
    }

    handlePrimaryMealPreference(event) {
        this.primaryMealPreference = event.detail.value;
    }

    // ---------------------------------------------------------------------------------
    // PAX handlers
    // ---------------------------------------------------------------------------------

    handlePaxCountChange(event) {
        const value = parseInt(event.detail.value, 10);
        if (Number.isNaN(value)) {
            return;
        }
        this.setPaxCount(value);
    }

    handleAddPax() {
        this.setPaxCount(this.paxRows.length + 1);
    }

    handleRemovePax(event) {
        const key = event.currentTarget.dataset.key;
        this.paxRows = relabel(this.paxRows.filter((r) => r.key !== key));
        this.paxCount = this.paxRows.length;
    }

    setPaxCount(value) {
        const count = Math.min(Math.max(value, 0), MAX_PAX);
        const rows = this.paxRows.slice(0, count);
        while (rows.length < count) {
            rows.push({ key: `pax-${++this.keySeq}`, guest: null, roomType: null, mealPreference: null });
        }
        this.paxRows = relabel(rows);
        this.paxCount = count;
    }

    handlePaxSelect(event) {
        this.updatePaxRow(event.target.dataset.key, { guest: event.detail });
    }

    handlePaxRemove(event) {
        this.updatePaxRow(event.target.dataset.key, { guest: null });
    }

    async handlePaxNewContact(event) {
        const key = event.target.dataset.key;
        const row = this.paxRows.find((r) => r.key === key);
        const guest = await this.openNewContact(
            `New PAX - ${row ? row.label : 'Traveller'}`,
            false,
            event.detail.searchTerm
        );
        if (guest) {
            this.updatePaxRow(key, { guest });
        }
    }

    handlePaxRoomType(event) {
        this.updatePaxRow(event.target.dataset.key, { roomType: event.detail.value });
    }

    handlePaxMealPreference(event) {
        this.updatePaxRow(event.target.dataset.key, { mealPreference: event.detail.value });
    }

    updatePaxRow(key, changes) {
        this.paxRows = this.paxRows.map((r) => (r.key === key ? { ...r, ...changes } : r));
    }

    async openNewContact(heading, isPrimaryGuest, searchTerm) {
        const result = await NewContactModal.open({
            size: 'medium',
            label: heading,
            heading,
            isPrimaryGuest,
            searchTerm
        });
        if (!result) {
            return null;
        }
        const duplicate = this.findGuestWithPassport(result.passportNumber);
        if (duplicate) {
            this.toast(
                'Duplicate passport',
                `Passport Number ${result.passportNumber} is already entered for ${duplicate.name}.`,
                'error'
            );
            return null;
        }
        return {
            id: `new-${++this.keySeq}`,
            contactId: null,
            isNew: true,
            name: [result.salutation, result.firstName, result.lastName].filter(Boolean).join(' '),
            subtitle: [result.mobile, `Passport: ${result.passportNumber}`].filter(Boolean).join(' • '),
            newContact: result
        };
    }

    findGuestWithPassport(passportNumber) {
        return [this.primaryGuest, ...this.paxRows.map((r) => r.guest)].find(
            (g) => g && g.isNew && g.newContact.passportNumber === passportNumber
        );
    }

    // ---------------------------------------------------------------------------------
    // Tour handlers
    // ---------------------------------------------------------------------------------

    handleTourMasterChange(event) {
        const value = event.detail.value;
        if (value === this.tourMasterId) {
            return;
        }
        this.tourMasterId = value;
        this.tourPlanId = null;
        this.tourPlans = [];
        this.optionalTours = [];
        this.selectedOptionalTourIds = [];
        this.isLoadingPlans = true;
        this.resetDiscounts();
    }

    handleTourPlanChange(event) {
        this.tourPlanId = event.detail.value;
        this.resetDiscounts();
    }

    handleApplyMaxDiscount(event) {
        const field = event.currentTarget.dataset.field;
        this[field] = field === 'standardDiscount' ? this.standardDiscountMax : this.specialDiscountMax;
    }

    resetDiscounts() {
        this.standardDiscount = null;
        this.specialDiscount = null;
    }

    // ---------------------------------------------------------------------------------
    // Generic field handlers
    // ---------------------------------------------------------------------------------

    handleCheckboxChange(event) {
        this[event.target.dataset.field] = event.target.checked;
    }

    handleFieldChange(event) {
        this[event.target.dataset.field] = event.detail.value;
    }

    handleNumberChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this[field] = value === '' || value == null ? null : Number(value);

        const adjustment = ADJUSTMENTS.find((a) => a.fields.includes(field));
        if (adjustment) {
            // Re-check both components so the error clears as soon as either one is filled
            if (this.applyAdjustmentValidity(adjustment)) {
                adjustment.fields.forEach((f) => {
                    const input = this.adjustmentInput(f);
                    if (input) {
                        input.reportValidity();
                    }
                });
            }
        }
    }

    /** Flags both components of a ticked adjustment when neither has a value. Returns true when valid. */
    applyAdjustmentValidity(adjustment) {
        const missing = this[adjustment.toggle] && !adjustment.fields.some((f) => num(this[f]) > 0);
        adjustment.fields.forEach((f) => {
            const input = this.adjustmentInput(f);
            if (input) {
                input.setCustomValidity(
                    missing ? `Enter the INR and/or Forex component for ${adjustment.label}.` : ''
                );
            }
        });
        return !missing;
    }

    adjustmentInput(field) {
        return this.template.querySelector(`lightning-input[data-field="${field}"]`);
    }

    handleOptionalTourChange(event) {
        this.selectedOptionalTourIds = event.detail.value;
    }

    // ---------------------------------------------------------------------------------
    // Save
    // ---------------------------------------------------------------------------------

    async handleCreateBooking() {
        if (!this.validate()) {
            return;
        }
        this.isSaving = true;
        try {
            const bookingId = await createBooking({ requestJson: JSON.stringify(this.buildRequest()) });
            this.toast('Booking created', 'The booking and its related records were created successfully.', 'success');
            this.resetForm();
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: bookingId, objectApiName: 'Booking__c', actionName: 'view' }
            });
        } catch (error) {
            this.showError('Booking could not be created', error);
        } finally {
            this.isSaving = false;
        }
    }

    validate() {
        ADJUSTMENTS.forEach((adjustment) => this.applyAdjustmentValidity(adjustment));
        const fields = [
            ...this.template.querySelectorAll(
                'c-contact-lookup, c-tour-plan-picker, lightning-input, lightning-combobox, lightning-textarea, lightning-checkbox-group'
            )
        ];
        const allValid = fields.reduce((valid, field) => field.reportValidity() && valid, true);
        if (!allValid) {
            this.toast('Review the form', 'Please fix the highlighted fields.', 'error');
            return false;
        }
        return true;
    }

    buildRequest() {
        const toGuestInput = (guest, roomType, mealPreference) => ({
            contactId: guest.contactId,
            newContact: guest.isNew ? guest.newContact : null,
            roomType,
            mealPreference: mealPreference || null
        });
        return {
            primaryGuest: toGuestInput(this.primaryGuest, this.primaryRoomType, this.primaryMealPreference),
            paxGuests: this.paxRows.map((r) => toGuestInput(r.guest, r.roomType, r.mealPreference)),
            tourMasterId: this.tourMasterId,
            tourPlanId: this.tourPlanId,
            exchangeRate: this.exchangeRate,
            additionInTourCost: this.additionInTourCost,
            inrAddition: this.additionInTourCost ? this.inrAddition : null,
            forexAddition: this.additionInTourCost ? this.forexAddition : null,
            reductionInTourCost: this.reductionInTourCost,
            inrReduction: this.reductionInTourCost ? this.inrReduction : null,
            forexReduction: this.reductionInTourCost ? this.forexReduction : null,
            standardDiscount: this.standardDiscount,
            specialDiscount: this.specialDiscount,
            optionalTourIds: this.includeOptionalTours ? this.selectedOptionalTourIds : [],
            nomineeName: this.nomineeName,
            nomineeContactNumber: this.nomineeContactNumber,
            relationWithNominee: this.relationWithNominee,
            remarks: this.remarks
        };
    }

    handleReset() {
        this.resetForm();
    }

    resetForm() {
        this.primaryGuest = null;
        this.primaryRoomType = null;
        this.primaryMealPreference = null;
        this.paxRows = [];
        this.paxCount = 0;
        this.tourMasterId = null;
        this.tourPlanId = null;
        this.tourPlans = [];
        this.optionalTours = [];
        this.isLoadingPlans = false;
        this.exchangeRate = null;
        this.additionInTourCost = false;
        this.inrAddition = null;
        this.forexAddition = null;
        this.reductionInTourCost = false;
        this.inrReduction = null;
        this.forexReduction = null;
        this.resetDiscounts();
        this.includeOptionalTours = false;
        this.selectedOptionalTourIds = [];
        this.nomineeName = null;
        this.nomineeContactNumber = null;
        this.relationWithNominee = null;
        this.remarks = null;
        this.template.querySelectorAll('c-contact-lookup').forEach((lookup) => lookup.reset());
    }

    // ---------------------------------------------------------------------------------
    // Utilities
    // ---------------------------------------------------------------------------------

    showError(title, error) {
        this.toast(title, reduceError(error), 'error');
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant, mode: variant === 'error' ? 'sticky' : 'dismissible' })
        );
    }
}

function relabel(rows) {
    return rows.map((r, i) => ({ ...r, label: `PAX ${i + 1}`, number: i + 1 }));
}

function toOptions(values) {
    return values.map((v) => ({ label: v.label, value: v.value }));
}

function num(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
}

function formatDate(value) {
    if (!value) {
        return '';
    }
    const [year, month, day] = value.split('-');
    return `${day}/${month}/${year}`;
}

function formatInr(value) {
    return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 }).format(
        value
    );
}

function reduceError(error) {
    if (!error) {
        return 'Unknown error';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && error.body.message) {
        return error.body.message;
    }
    return error.message || 'Unknown error';
}