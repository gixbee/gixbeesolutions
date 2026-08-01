/** Booking-lifecycle outbox event types (partial conversion — no CQRS). */
export const OutboxEventType = {
  BOOKING_BROADCAST_CREATED: 'booking.broadcast_created',
  BOOKING_ACCEPTED: 'booking.accepted',
  BOOKING_CANCELLED: 'booking.cancelled',
  BOOKING_COMPLETED: 'booking.completed',
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
  /**
   * Fan-out wave: 1 = initial broadcast (schedules the first 90s timeout,
   * WRITES the notified set), 2 = widened rebroadcast after nobody accepted
   * (timeout already scheduled by rebroadcastBooking, MERGES the notified
   * set). Absent = legacy event → treated as 1.
   */
  attempt?: number;
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
  /** customer | timeout | sibling_accept | system | WORKER_NO_PROGRESS */
  source:
    | 'customer'
    | 'operator'
    | 'timeout'
    | 'sibling_accept'
    | 'system'
    | 'WORKER_NO_PROGRESS';
  operatorId: string | null;
  operatorName: string | null;
  customerId: string | null;
  /** Extra worker ids that had this request in pending (broadcast fan-out). */
  notifyWorkerIds?: string[];
}

export interface BookingCompletedPayload {
  bookingId: string;
  customerId: string | null;
  operatorId: string | null;
  operatorName: string | null;
  isPaid: boolean;
  workerPaidConfirmed: boolean;
  customerPaidConfirmed: boolean;
}

export interface BookingPaymentConfirmedPayload {
  bookingId: string;
  customerId: string | null;
  operatorId: string | null;
  operatorName: string | null;
  /** Booking status string (usually COMPLETED). */
  status: string;
  isPaid: boolean;
  workerPaidConfirmed: boolean;
  customerPaidConfirmed: boolean;
  pauseRequested?: boolean;
  paused?: boolean;
  pausedMinutes?: number;
}
