import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

/** Booking quick action: Tour Cost Calculation PDF */
export default class TourCostPdfAction extends LightningElement {
    @api recordId;

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}