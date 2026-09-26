import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/booking_repository.dart';
import '../business/hiring_requests_screen.dart';
import '../events/event_plan_detail_screen.dart';
import '../jobs/application_tracker_screen.dart';
import '../jobs/booking_detail_screen.dart';
import '../jobs/my_bookings_screen.dart';
import '../rentals/my_rentals_screen.dart';
import '../rentals/owner_rentals_screen.dart';
import '../../shared/models/business.dart';

/// Opens the established detail flow for an activity feed row.
/// Returns `true` when the user may have changed the underlying record.
Future<bool> openActivityDetail(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final detail = item['detail'];
  if (detail is! Map) return false;
  final kind = detail['kind']?.toString() ?? '';
  final id = detail['id']?.toString() ?? item['id']?.toString() ?? '';
  final extra = detail['extra'] is Map
      ? Map<String, dynamic>.from(detail['extra'] as Map)
      : <String, dynamic>{};

  switch (kind) {
    case 'booking':
      final booking =
          await ref.read(bookingRepositoryProvider).getBookingById(id);
      if (booking == null || !context.mounted) return false;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(booking: booking),
        ),
      );
      ref.invalidate(myBookingsProvider);
      return true;
    case 'rental_reservation':
      final asOwner = extra['asOwner'] == true;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => asOwner
              ? OwnerRentalsScreen(
                  businessId: extra['businessId']?.toString(),
                  initialReservationId: id,
                )
              : MyRentalsScreen(initialReservationId: id),
        ),
      );
      return true;
    case 'event_plan':
    case 'event_quote':
      final planId =
          (kind == 'event_quote' ? extra['planId'] : id)?.toString() ?? id;
      Business? business;
      final bid = extra['businessId']?.toString();
      if (bid != null && bid.isNotEmpty) {
        business = Business(
          id: bid,
          name: 'Vendor',
          type: 'SERVICE',
          ownerId: '',
          status: 'VERIFIED',
        );
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventPlanDetailScreen(
            planId: planId,
            business: business,
          ),
        ),
      );
      return true;
    case 'job_application':
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ApplicationTrackerScreen(focusApplicationId: id),
        ),
      );
      return true;
    case 'hiring_request':
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HiringRequestDetailScreen(requestId: id),
        ),
      );
      return true;
    default:
      return false;
  }
}

/// Legacy service booking tabs (Upcoming / Active / Past).
Future<void> openServiceBookingsLegacy(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
  );
}
