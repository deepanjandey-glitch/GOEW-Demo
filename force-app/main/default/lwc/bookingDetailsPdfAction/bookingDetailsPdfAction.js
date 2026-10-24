import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

/** Booking quick action: Booking Details PDF */
export default class BookingDetailsPdfAction extends LightningElement {
    @api recordId;

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}