/** Booking-lifecycle outbox event types (partial conversion — no CQRS). */
export const OutboxEventType = {
  BOOKING_BROADCAST_CREATED: 'booking.broadcast_created',
  BOOKING_ACCEPTED: 'booking.accepted',
  BOOKING_CANCELLED: 'booking.cancelled',
  /** TODO: wire from verifyCompletionOtp */
  BOOKING_COMPLETED: 'booking.completed',
  /** TODO: wire from markPaid when isPaid flips true */
  BOOKING_PAYMENT_CONFIRMED: 'booking.payment_confirmed',
} as const;

export type OutboxEventTypeName =
  (typeof OutboxEventType)[keyof typeof OutboxEventType];

export interface BookingBroadcastCreatedPayload {
  bookingId: string;
  customerId: string;
  /** Customer's first name for the worker's incoming card (no full name pre-accept). */
  customerName?: string;
  skill: string;
  serviceLocation: string;
  /** Job coordinates — lets the worker's card compute "2.3 km away" locally. */
  serviceLat?: number;
  serviceLng?: number;
  /** INSTANT broadcast: the customer's offered ₹/hr rate — NOT a flat job total. */
  amount: number;
  description?: string;
  preferredLanguages?: string[];
  /** Booking creation time (ISO) — anchors the worker-side accept countdown. */
  createdAt?: string;
  arrivalOtp: string;
  completionOtp: string;
  notifiedWorkerIds: string[];
}

export interface BookingAcceptedPayload {
  bookingId: string;
  workerId: string;
  customerId: string | null;
  operatorName: string | null;
  arrivalOtp: string | null;
  cancelledBookingIds: string[];
  cancelledCustomerIds: string[];
}

export interface BookingCancelledPayload {
  bookingId: string;
  reason: string;
  /** customer | timeout | sibling_accept | system */
  source: 'customer' | 'timeout' | 'sibling_accept' | 'system';
  operatorId: string | null;
  operatorName: string | null;
  customerId: string | null;
  /** Extra worker ids that had this request in pending (broadcast fan-out). */
  notifyWorkerIds?: string[];
}
