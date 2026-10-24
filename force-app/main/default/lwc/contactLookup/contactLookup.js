import { LightningElement, api } from 'lwc';
import searchContacts from '@salesforce/apex/CreateBookingController.searchContacts';

const DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;

/**
 * Searchable Contact lookup with an inline "New Contact" option.
 *
 * Events:
 *  - select      detail: { id, contactId, name, subtitle, isNew: false }
 *  - remove      (selection cleared)
 *  - newcontact  detail: { searchTerm }  (parent opens the create-contact modal)
 */
export default class ContactLookup extends LightningElement {
    @api label;
    @api required = false;
    @api placeholder = 'Search by name, mobile, email or passport...';
    @api newContactLabel = 'New Contact';
    @api excludeIds = [];
    /** Current selection: { id, contactId, name, subtitle, isNew } */
    @api selection;

    searchTerm = '';
    results = [];
    isLoading = false;
    hasFocus = false;
    searchTimeout;
    requestSeq = 0;

    get hasSelection() {
        return !!this.selection;
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${
            this.hasFocus ? ' slds-is-open' : ''
        }`;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get showNoResults() {
        return !this.isLoading && !this.hasResults && this.searchTerm.trim().length >= MIN_SEARCH_LENGTH;
    }

    get showSearchHint() {
        return this.searchTerm.trim().length < MIN_SEARCH_LENGTH;
    }

    get newContactText() {
        const term = this.searchTerm.trim();
        return term ? `${this.newContactLabel}: "${term}"` : this.newContactLabel;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        this.clearCustomValidity();
        window.clearTimeout(this.searchTimeout);

        if (this.searchTerm.trim().length < MIN_SEARCH_LENGTH) {
            this.results = [];
            this.isLoading = false;
            return;
        }
        this.isLoading = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimeout = window.setTimeout(() => this.runSearch(), DEBOUNCE_MS);
    }

    async runSearch() {
        const seq = ++this.requestSeq;
        try {
            const records = await searchContacts({
                searchKey: this.searchTerm.trim(),
                excludeIds: (this.excludeIds || []).filter(Boolean)
            });
            if (seq !== this.requestSeq) {
                return;
            }
            this.results = records.map((c) => ({
                id: c.Id,
                contactId: c.Id,
                name: c.Name,
                subtitle: buildSubtitle(c),
                isNew: false
            }));
        } catch (error) {
            if (seq === this.requestSeq) {
                this.results = [];
            }
        } finally {
            if (seq === this.requestSeq) {
                this.isLoading = false;
            }
        }
    }

    handleFocus() {
        this.hasFocus = true;
    }

    handleBlur() {
        this.hasFocus = false;
    }

    // mousedown (not click) so the choice is registered before the input's blur closes the list
    handleResultMouseDown(event) {
        event.preventDefault();
        const record = this.results.find((r) => r.id === event.currentTarget.dataset.id);
        if (!record) {
            return;
        }
        this.resetSearch();
        this.dispatchEvent(new CustomEvent('select', { detail: { ...record } }));
    }

    handleNewContactMouseDown(event) {
        event.preventDefault();
        const searchTerm = this.searchTerm.trim();
        this.hasFocus = false;
        this.dispatchEvent(new CustomEvent('newcontact', { detail: { searchTerm } }));
    }

    handleRemove() {
        this.resetSearch();
        this.dispatchEvent(new CustomEvent('remove'));
    }

    @api
    reset() {
        this.resetSearch();
    }

    @api
    reportValidity() {
        if (this.hasSelection) {
            return true;
        }
        const input = this.template.querySelector('lightning-input');
        if (!input) {
            return !this.required;
        }
        input.setCustomValidity(
            this.searchTerm.trim() ? 'Select a contact from the list or create a new one.' : ''
        );
        return input.reportValidity();
    }

    clearCustomValidity() {
        const input = this.template.querySelector('lightning-input');
        if (input) {
            input.setCustomValidity('');
        }
    }

    resetSearch() {
        window.clearTimeout(this.searchTimeout);
        this.requestSeq++;
        this.searchTerm = '';
        this.results = [];
        this.isLoading = false;
        this.hasFocus = false;
    }
}

function buildSubtitle(contact) {
    return [
        contact.MobilePhone,
        contact.Email,
        contact.Passport_Number__c ? `Passport: ${contact.Passport_Number__c}` : null
    ]
        .filter(Boolean)
        .join(' • ');
}