import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { loadStyle } from 'lightning/platformResourceLoader';
import FORM_FACTOR from '@salesforce/client/formFactor';
import MODAL_STYLES from '@salesforce/resourceUrl/bookingPdfModal';
import savePdf from '@salesforce/apex/BookingPdfService.savePdf';

const PDF_TYPES = {
    bookingDetails: { page: 'BookingPage', title: 'Booking Details', icon: 'doctype:pdf' },
    tourCost: { page: 'TourCostCalculationPage', title: 'Tour Cost Calculation', icon: 'doctype:pdf' }
};

/**
 * Previews a Booking PDF (Visualforce, renderAs="pdf") and lets the user download it
 * or save it to the booking's Files. Used by the Booking quick actions.
 *
 * Events: close - the user is done (the host quick action closes the panel)
 */
export default class BookingPdfViewer extends LightningElement {
    @api recordId;
    /** bookingDetails | tourCost */
    @api pdfType;

    isLoading = true;
    isSaving = false;

    connectedCallback() {
        // Widens the quick action modal so the PDF is readable; scoped to modals hosting this component
        loadStyle(this, MODAL_STYLES).catch(() => {
            // Cosmetic only - the default modal width still works
        });
    }

    get config() {
        return PDF_TYPES[this.pdfType] || PDF_TYPES.bookingDetails;
    }

    get title() {
        return this.config.title;
    }

    get pageUrl() {
        return this.recordId ? `/apex/${this.config.page}?id=${this.recordId}` : null;
    }

    get downloadUrl() {
        return this.pageUrl ? `${this.pageUrl}&download=1` : null;
    }

    get isPhone() {
        return FORM_FACTOR === 'Small';
    }

    get showSpinner() {
        return this.isSaving || (this.isLoading && !this.isPhone);
    }

    get isBusy() {
        return this.isSaving || !this.recordId;
    }

    handleFrameLoad() {
        this.isLoading = false;
    }

    handleDownload() {
        window.open(this.downloadUrl, '_blank');
    }

    handleOpen() {
        window.open(this.pageUrl, '_blank');
    }

    async handleSave() {
        this.isSaving = true;
        try {
            await savePdf({ bookingId: this.recordId, pdfType: this.pdfType });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `${this.title} saved`,
                    message: 'The PDF has been attached to the Files of this booking.',
                    variant: 'success'
                })
            );
            // Refresh the Files related list on the record page
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'The PDF could not be saved',
                    message: (error && error.body && error.body.message) || (error && error.message) || 'Unknown error',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}