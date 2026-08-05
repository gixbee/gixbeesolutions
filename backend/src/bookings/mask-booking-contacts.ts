import { Booking } from './booking.entity';

/**
 * NUMBER MASKING for participant-facing booking responses.
 *
 * Customers and pros reach each other through in-app WebRTC voice, so neither
 * side ever needs the other's real number. Leaving `customer.phoneNumber`,
 * `operator.phoneNumber` and `onSiteContact.phone` in the payload meant the
 * number was one API response away even after the dialer button was removed.
 *
 * Fields are set to undefined rather than deleted so the entity instance keeps
 * its class identity — the global ClassSerializerInterceptor must still run to
 * strip @Exclude'd fields such as walletBalance and fcmToken. JSON.stringify
 * drops undefined values, so nothing reaches the wire.
 *
 * Admin endpoints deliberately do NOT call this; support staff need the real
 * numbers to resolve disputes.
 */
export function maskBookingContacts<T extends Partial<Booking>>(booking: T): T {
  if (!booking) return booking;
  if (booking.customer) booking.customer.phoneNumber = undefined as never;
  if (booking.operator) booking.operator.phoneNumber = undefined as never;
  if (booking.onSiteContact) {
    booking.onSiteContact = {
      ...booking.onSiteContact,
      phone: undefined as never,
    };
  }
  return booking;
}

export function maskBookingContactsList<T extends Partial<Booking>>(
  bookings: T[],
): T[] {
  for (const b of bookings) maskBookingContacts(b);
  return bookings;
}
