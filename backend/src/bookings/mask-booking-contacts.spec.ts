import {
  maskBookingContacts,
  maskBookingContactsList,
} from './mask-booking-contacts';

describe('maskBookingContacts', () => {
  it('strips phone numbers and OTP fields from participant-facing payloads', () => {
    const booking: any = {
      id: 'b1',
      arrivalOtp: '1234',
      completionOtp: '5678',
      customer: { id: 'c1', phoneNumber: '9999999999' },
      operator: { id: 'w1', phoneNumber: '8888888888' },
      onSiteContact: { name: 'Raj', phone: '7777777777' },
    };

    maskBookingContacts(booking);

    expect(booking.arrivalOtp).toBeUndefined();
    expect(booking.completionOtp).toBeUndefined();
    expect(booking.customer.phoneNumber).toBeUndefined();
    expect(booking.operator.phoneNumber).toBeUndefined();
    expect(booking.onSiteContact.phone).toBeUndefined();
    expect(booking.id).toBe('b1');
  });

  it('maskBookingContactsList applies masking to every row', () => {
    const rows: any[] = [
      { id: 'b1', arrivalOtp: '1111', completionOtp: '2222' },
      { id: 'b2', arrivalOtp: '3333', completionOtp: '4444' },
    ];

    maskBookingContactsList(rows);

    expect(rows[0].arrivalOtp).toBeUndefined();
    expect(rows[1].completionOtp).toBeUndefined();
  });
});
