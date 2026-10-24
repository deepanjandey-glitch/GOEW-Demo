import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CONTACT_OBJECT from '@salesforce/schema/Contact';
import SALUTATION_FIELD from '@salesforce/schema/Contact.Salutation';

const MOBILE_PATTERN = /^\+?\d{7,15}$/;

/**
 * Collects the details of a new Contact. Nothing is saved here: the modal closes with the
 * entered values and the contact is inserted together with the booking.
 */
export default class NewContactModal extends LightningModal {
    @api heading = 'New Contact';
    /** Mobile and PAN are shown (and mandatory) for the primary guest only; PAX do not need them */
    @api isPrimaryGuest = false;
    /** Text typed in the lookup, used to prefill the name */
    @api searchTerm;

    contact = {};
    salutationOptions = [];

    @wire(getObjectInfo, { objectApiName: CONTACT_OBJECT })
    contactInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$contactInfo.data.defaultRecordTypeId',
        fieldApiName: SALUTATION_FIELD
    })
    wiredSalutations({ data }) {
        if (data) {
            this.salutationOptions = data.values.map((v) => ({ label: v.label, value: v.value }));
        }
    }

    connectedCallback() {
        const term = (this.searchTerm || '').trim();
        // Prefill the name only when the search looked like a name (not a phone/passport number)
        if (term && !/\d/.test(term)) {
            const parts = term.split(/\s+/);
            const lastName = parts.pop();
            this.contact = { firstName: parts.join(' '), lastName };
        }
    }

    get today() {
        const now = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        let value = event.detail.value;
        if ((field === 'pan' || field === 'passportNumber') && value) {
            value = value.toUpperCase();
        }
        this.contact = { ...this.contact, [field]: value };
        event.target.setCustomValidity('');
    }

    handleCancel() {
        this.close(null);
    }

    handleSave() {
        const mobile = this.template.querySelector('[data-field="mobile"]');
        if (mobile) {
            const mobileDigits = (this.contact.mobile || '').replace(/[\s-]/g, '');
            mobile.setCustomValidity(
                mobileDigits && !MOBILE_PATTERN.test(mobileDigits) ? 'Enter a valid mobile number.' : ''
            );
        }

        const expiry = this.template.querySelector('[data-field="dateOfExpiry"]');
        const { dateOfIssue, dateOfExpiry } = this.contact;
        expiry.setCustomValidity(
            dateOfIssue && dateOfExpiry && dateOfExpiry <= dateOfIssue
                ? 'Date of Expiry must be after Date of Issue.'
                : ''
        );

        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        const isValid = inputs.reduce((valid, input) => input.reportValidity() && valid, true);
        if (!isValid) {
            return;
        }

        const trim = (v) => (v ? v.trim() : v);
        this.close({
            salutation: this.contact.salutation,
            firstName: trim(this.contact.firstName),
            lastName: trim(this.contact.lastName),
            mobile: this.isPrimaryGuest ? trim(this.contact.mobile) : null,
            pan: this.isPrimaryGuest ? trim(this.contact.pan) : null,
            dateOfBirth: this.contact.dateOfBirth,
            passportNumber: trim(this.contact.passportNumber),
            dateOfIssue: dateOfIssue,
            dateOfExpiry: dateOfExpiry
        });
    }
}