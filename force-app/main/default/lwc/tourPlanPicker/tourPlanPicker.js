import { LightningElement, api } from 'lwc';

// The departure-date part of a Tour Plan name is shown in bold:
// - from the last "-" followed by a number, e.g. "SPARKLE OF EUROPE - 09 JULY 2027", "JOYFUL JAPAN - 30 MAR 2026 TG"
// - otherwise a trailing day + month (+ year), e.g. "TRANS SIBERIAN SAGA 10 AUGUST", "LYRICAL LAKE DISTRICT 31 MAY 2027"
const DASH_DATE = /^(.*\S)(\s*-\s*\d[\s\S]*)$/;
const TRAILING_DATE = /^(.*?\S)(\s+\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]{3,}\.?(?:,?\s+\d{2,4})?)\s*$/i;

/**
 * Single-select dropdown for Tour Plans that shows the date part of each plan name in bold
 * (lightning-combobox only renders plain-text labels).
 *
 * options: [{ label, value }]   Events: change - detail: { value }
 */
export default class TourPlanPicker extends LightningElement {
    @api label;
    @api placeholder = 'Select';
    @api required = false;
    @api disabled = false;
    @api value;
    @api messageWhenValueMissing = 'Complete this field.';

    _options = [];
    isOpen = false;
    activeIndex = -1;
    showError = false;
    scrollToActive = false;

    @api
    get options() {
        return this._options;
    }
    set options(value) {
        this._options = (value || []).map((option) => ({ ...option, ...splitName(option.label) }));
    }

    @api
    reportValidity() {
        const valid = this.checkValidity();
        this.showError = !valid;
        return valid;
    }

    @api
    checkValidity() {
        return !this.required || this.disabled || !!this.value;
    }

    get selected() {
        return this._options.find((o) => o.value === this.value);
    }

    get hasSelection() {
        return !!this.selected;
    }

    get selectedName() {
        return this.selected ? this.selected.name : '';
    }

    get selectedDate() {
        return this.selected ? this.selected.dateText : '';
    }

    get selectedTitle() {
        return this.selected ? this.selected.label : this.placeholder;
    }

    get noOptions() {
        return this._options.length === 0;
    }

    get viewOptions() {
        return this._options.map((option, index) => {
            const isSelected = option.value === this.value;
            return {
                ...option,
                index,
                isSelected,
                ariaSelected: String(isSelected),
                className:
                    'slds-media slds-listbox__option slds-listbox__option_plain slds-media_small option' +
                    (index === this.activeIndex ? ' slds-has-focus' : '')
            };
        });
    }

    get formElementClass() {
        return `slds-form-element${this.showError ? ' slds-has-error' : ''}`;
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${this.isOpen ? ' slds-is-open' : ''}`;
    }

    get triggerClass() {
        return `slds-input_faux slds-combobox__input trigger${this.hasSelection ? ' slds-combobox__input-value' : ''}`;
    }

    get ariaExpanded() {
        return String(this.isOpen);
    }

    renderedCallback() {
        if (this.scrollToActive) {
            this.scrollToActive = false;
            const active = this.template.querySelector(`[data-index="${this.activeIndex}"]`);
            if (active) {
                active.scrollIntoView({ block: 'nearest' });
            }
        }
    }

    handleToggle() {
        if (this.disabled) {
            return;
        }
        if (this.isOpen) {
            this.close();
        } else {
            this.open();
        }
    }

    handleBlur() {
        this.close();
    }

    // mousedown (not click) so the choice is made before the trigger's blur closes the list
    handleOptionMouseDown(event) {
        event.preventDefault();
        this.select(Number(event.currentTarget.dataset.index));
    }

    handleKeyDown(event) {
        if (this.disabled) {
            return;
        }
        const last = this._options.length - 1;
        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                if (!this.isOpen) {
                    this.open();
                } else {
                    this.moveTo(Math.min(this.activeIndex + 1, last));
                }
                break;
            case 'ArrowUp':
                event.preventDefault();
                if (!this.isOpen) {
                    this.open();
                } else {
                    this.moveTo(Math.max(this.activeIndex - 1, 0));
                }
                break;
            case 'Home':
                if (this.isOpen) {
                    event.preventDefault();
                    this.moveTo(0);
                }
                break;
            case 'End':
                if (this.isOpen) {
                    event.preventDefault();
                    this.moveTo(last);
                }
                break;
            case 'Enter':
            case ' ':
                event.preventDefault();
                if (this.isOpen && this.activeIndex >= 0) {
                    this.select(this.activeIndex);
                } else {
                    this.handleToggle();
                }
                break;
            case 'Escape':
                if (this.isOpen) {
                    event.preventDefault();
                    this.close();
                }
                break;
            default:
        }
    }

    open() {
        this.isOpen = true;
        const selectedIndex = this._options.findIndex((o) => o.value === this.value);
        this.moveTo(selectedIndex >= 0 ? selectedIndex : 0);
    }

    close() {
        this.isOpen = false;
        this.activeIndex = -1;
    }

    moveTo(index) {
        this.activeIndex = index;
        this.scrollToActive = true;
    }

    select(index) {
        const option = this._options[index];
        this.close();
        if (!option) {
            return;
        }
        this.showError = false;
        if (option.value !== this.value) {
            this.dispatchEvent(new CustomEvent('change', { detail: { value: option.value } }));
        }
    }
}

function splitName(label) {
    const text = label || '';
    const match = DASH_DATE.exec(text) || TRAILING_DATE.exec(text);
    return match ? { name: match[1], dateText: match[2] } : { name: text, dateText: '' };
}