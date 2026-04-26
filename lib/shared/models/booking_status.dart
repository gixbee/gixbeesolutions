/// Booking lifecycle status enum.
/// Replaces ALL inline string comparisons across the app.
enum BookingStatus {
  requested,
  customRequested,
  pending,
  confirmed,
  accepted,
  arrived,
  active,
  inProgress,
  completed,
  cancelled,
  rejected,
  unknown;

  static const _map = {
    'REQUESTED': BookingStatus.requested,
    'CUSTOM_REQUESTED': BookingStatus.customRequested,
    'PENDING': BookingStatus.pending,
    'CONFIRMED': BookingStatus.confirmed,
    'ACCEPTED': BookingStatus.accepted,
    'ARRIVED': BookingStatus.arrived,
    'ACTIVE': BookingStatus.active,
    'IN_PROGRESS': BookingStatus.inProgress,
    'COMPLETED': BookingStatus.completed,
    'CANCELLED': BookingStatus.cancelled,
    'REJECTED': BookingStatus.rejected,
  };

  static BookingStatus fromString(String value) =>
      _map[value.toUpperCase()] ?? BookingStatus.unknown;

  bool get isActive =>
      this == active || this == inProgress || this == arrived || this == accepted;

  bool get isTerminal =>
      this == completed || this == cancelled || this == rejected;
}
