/// Booking lifecycle status enum.
/// Replaces inline string comparisons like `status == 'ACCEPTED'`.
enum BookingStatus {
  pending,
  accepted,
  cancelled,
  rejected;

  /// Parse a backend status string (e.g. "ACCEPTED") into the enum.
  static BookingStatus fromString(String value) {
    return BookingStatus.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => BookingStatus.pending,
    );
  }
}
