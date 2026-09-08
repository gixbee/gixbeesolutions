import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../repositories/auth_repository.dart';
import '../../services/ola_maps_style_service.dart';
import '../booking/completion_otp_screen.dart';
import '../booking/live_tracking_map_screen.dart';
import '../jobs/booking_detail_screen.dart';
import '../../shared/models/worker.dart';
import '../../shared/widgets/glass_container.dart';
import '../booking/collect_payment_screen.dart';
import '../booking/customer_pay_screen.dart';
import '../../shared/utils/api_error_message.dart';
import '../../shared/utils/booking_flags.dart';
import '../../theme.dart';

// Derives from shared myBookingsProvider — auto-refreshes on invalidation.
// API failures propagate (do not collapse to null/"no booking").
final activeBookingProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final bookings = await ref.watch(myBookingsProvider.future);
  const activeStatuses = [
    'REQUESTED',
    'PENDING',
    'ACCEPTED',
    'ARRIVED',
    'ACTIVE',
    'IN_PROGRESS',
    'CONFIRMED',
  ];
  for (final b in bookings) {
    final status = (b['status'] ?? '').toString().toUpperCase();
    if (activeStatuses.contains(status)) {
      return Map<String, dynamic>.from(b as Map);
    }
    // Unpaid completed jobs still need the manual payment screens.
    if (status == 'COMPLETED' && !bookingFlagTrue(b['isPaid'])) {
      return Map<String, dynamic>.from(b as Map);
    }
  }
  return null;
});

class ActiveBookingCard extends ConsumerStatefulWidget {
  const ActiveBookingCard({super.key});

  @override
  ConsumerState<ActiveBookingCard> createState() => _ActiveBookingCardState();
}

class _ActiveBookingCardState extends ConsumerState<ActiveBookingCard> {
  // AUDIT FIX: this card ran its OWN 10s poll, duplicating the tracking
  // screen's and the job-controls' polls for the same booking. It now watches
  // the shared bookingStatusProvider — one poll per booking, app-wide, with
  // background pausing handled inside that provider.
  String? _liveStatus;
  String? _lastTerminalId; // avoid re-invalidating the list on every rebuild
  String? _lastPaidRefreshId;

  /// Terminal transitions still need the bookings list refreshed.
  void _onStatus(String bookingId, Map<String, dynamic>? polled) {
    final newStatus = polled?['status']?.toString().toUpperCase();
    if (newStatus == null || newStatus == _liveStatus) {
      // Still watch isPaid flips on an already-COMPLETED booking.
      if (newStatus == 'COMPLETED' &&
          bookingFlagTrue(polled?['isPaid']) &&
          _lastPaidRefreshId != bookingId) {
        _lastPaidRefreshId = bookingId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.invalidate(myBookingsProvider);
            ref.invalidate(activeBookingProvider);
          }
        });
      }
      return;
    }
    _liveStatus = newStatus;
    if (['COMPLETED', 'CANCELLED', 'REJECTED'].contains(newStatus) &&
        _lastTerminalId != bookingId) {
      _lastTerminalId = bookingId;
      // Defer: we're inside build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(myBookingsProvider);
      });
    }
    if (newStatus == 'COMPLETED' &&
        bookingFlagTrue(polled?['isPaid']) &&
        _lastPaidRefreshId != bookingId) {
      _lastPaidRefreshId = bookingId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.invalidate(myBookingsProvider);
          ref.invalidate(activeBookingProvider);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final activeAsync = ref.watch(activeBookingProvider);

    if (user == null) return const SizedBox.shrink();

    return activeAsync.when(
      data: (activeBooking) {
        if (activeBooking == null) {
          _liveStatus = null;
          return const SizedBox.shrink();
        }

        final bookingId = activeBooking['id']?.toString() ?? '';

        // Shared status poll (one per booking, app-wide) — no local timer.
        final polled = bookingId.isEmpty
            ? null
            : ref.watch(bookingStatusProvider(bookingId)).value;
        if (bookingId.isNotEmpty) _onStatus(bookingId, polled);

        final polledStatus = polled?['status']?.toString().toUpperCase();
        final bStatus = polledStatus ??
            (activeBooking['status'] ?? '').toString().toUpperCase();
        final isPaid = bookingFlagTrue(polled?['isPaid']) ||
            bookingFlagTrue(activeBooking['isPaid']);

        // Both sides confirmed — drop pending-payment card immediately.
        if (bStatus == 'COMPLETED' && isPaid) {
          return const SizedBox.shrink();
        }

        final operatorId = activeBooking['operator']?['id'] ??
            activeBooking['operatorId'];
        final isOperator =
            user.id == operatorId?.toString();
        final workerConfirmed = bookingFlagTrue(polled?['workerPaidConfirmed']) ||
            bookingFlagTrue(activeBooking['workerPaidConfirmed']);
        final customerConfirmed =
            bookingFlagTrue(polled?['customerPaidConfirmed']) ||
                bookingFlagTrue(activeBooking['customerPaidConfirmed']);
        final iConfirmed =
            isOperator ? workerConfirmed : customerConfirmed;
        final dtRaw = activeBooking['scheduledAt'] != null
            ? (DateTime.tryParse(activeBooking['scheduledAt'].toString()) ?? DateTime.now())
            : (activeBooking['createdAt'] != null
                ? (DateTime.tryParse(activeBooking['createdAt'].toString()) ?? DateTime.now())
                : DateTime.now());
        final scheduledAt = dtRaw.toLocal();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GestureDetector(
            onTap: () async {
              if (bStatus == 'REQUESTED' || bStatus == 'PENDING') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          BookingDetailScreen(booking: activeBooking)),
                );
              } else if (bStatus == 'ACCEPTED' || bStatus == 'ARRIVED') {
                final operatorData = activeBooking['operator'];
                final workerName = operatorData?['name'] ??
                    activeBooking['operatorName'] ??
                    'Worker';
                final workerId = operatorData?['id']?.toString() ??
                    activeBooking['operatorId']?.toString() ??
                    '';
                final customerData = activeBooking['customer'];
                final customerName = customerData?['name'] ??
                    activeBooking['customerName'] ??
                    'Customer';
                final otp = activeBooking['arrivalOtp']?.toString();
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveTrackingMapScreen(
                      bookingId: bookingId,
                      worker: Worker(
                        id: workerId,
                        name: workerName,
                        title: activeBooking['skill'] ?? 'Professional',
                        bio: '',
                        imageUrl: operatorData?['profileImageUrl'] ?? '',
                        rating: 0,
                        completedJobs: 0,
                        reviewCount: 0,
                        isFeatured: false,
                        hourlyRate: 0,
                        skills: [],
                        availabilityTags: [],
                        primaryType: SkillType.manual,
                        status: 'available',
                      ),
                      customerLat: readCoord(activeBooking['serviceLat']),
                      customerLng: readCoord(activeBooking['serviceLng']),
                      arrivalOtp: otp,
                      isWorker: isOperator,
                      customerName: customerName,
                    ),
                  ),
                );
              } else if (bStatus == 'ACTIVE' || bStatus == 'IN_PROGRESS') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompletionOtpScreen(
                      bookingId: activeBooking['id'],
                      workerName:
                          activeBooking['operator']?['name'] ?? 'Worker',
                      isWorker: isOperator,
                    ),
                  ),
                );
              } else if (bStatus == 'COMPLETED' && !isPaid) {
                final amount = (num.tryParse(
                            '${activeBooking['totalAmount'] ?? activeBooking['amount'] ?? 0}') ??
                        0)
                    .toDouble();
                final hourlyRate = (num.tryParse(
                            '${activeBooking['hourlyRate'] ?? (activeBooking['type']?.toString().toUpperCase() == 'INSTANT' ? activeBooking['amount'] : 0) ?? 0}') ??
                        0)
                    .toDouble();
                final workedMinutes = (num.tryParse(
                            '${activeBooking['workedMinutes'] ?? ((activeBooking['billingHours'] != null) ? (num.tryParse('${activeBooking['billingHours']}') ?? 1) * 60 : 60)}') ??
                        60)
                    .round();

                if (isOperator) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectPaymentScreen(
                        bookingId: bookingId,
                        amount: amount,
                        customerName:
                            activeBooking['customer']?['name'] ?? 'Customer',
                        hourlyRate: hourlyRate > 0 ? hourlyRate : null,
                        workedMinutes: workedMinutes,
                        initiallyWaiting: iConfirmed,
                      ),
                    ),
                  );
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerPayScreen(
                        bookingId: bookingId,
                        amount: amount,
                        workerName:
                            activeBooking['operator']?['name'] ?? 'Worker',
                        hourlyRate: hourlyRate > 0 ? hourlyRate : null,
                        workedMinutes: workedMinutes,
                        initiallyWaiting: iConfirmed,
                      ),
                    ),
                  );
                }
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          BookingDetailScreen(booking: activeBooking)),
                );
              }
              // Full refresh after returning from a sub-screen
              _liveStatus = null;
              _lastPaidRefreshId = null;
              ref.invalidate(myBookingsProvider);
              if (bookingId.isNotEmpty) {
                ref.invalidate(bookingStatusProvider(bookingId));
              }
            },
            child: GlassContainer(
              padding: const EdgeInsets.all(16),
              opacity: 0.08,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getStatusColor(bStatus, iConfirmed)
                          .withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getStatusIcon(bStatus, iConfirmed),
                      color: _getStatusColor(bStatus, iConfirmed),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOperator ? 'Active Job' : 'Current Booking',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          '${activeBooking['serviceName'] ?? activeBooking['skill'] ?? 'General Help'} • ${DateFormat('hh:mm a').format(scheduledAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(bStatus, iConfirmed)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusLabel(bStatus, iConfirmed),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(bStatus, iConfirmed),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(Icons.arrow_forward_ios,
                          size: 12,
                          color: context.gx.ink.withValues(alpha: 0.45)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      // Compact inline retry — a full-page error state would shove the home
      // feed down for what is usually a one-tick network blip.
      error: (err, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Material(
          color: context.gx.card2,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              ref.invalidate(myBookingsProvider);
              ref.invalidate(activeBookingProvider);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 18,
                      color: context.gx.ink.withValues(alpha: 0.55)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      apiErrorMessage(
                        err,
                        fallback: 'Could not load bookings. Tap to retry.',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.gx.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Icon(Icons.refresh,
                      size: 18, color: context.gx.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status, bool waitingConfirm) {
    switch (status) {
      case 'REQUESTED':
      case 'PENDING':
        return Icons.hourglass_top_rounded;
      case 'ACCEPTED':
        return Icons.check_circle_outline;
      case 'ARRIVED':
        return Icons.place_outlined;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        return Icons.run_circle_outlined;
      case 'COMPLETED':
        return waitingConfirm
            ? Icons.hourglass_bottom_rounded
            : Icons.payments_outlined;
      default:
        return Icons.bookmark_outline;
    }
  }

  Color _getStatusColor(String status, bool waitingConfirm) {
    switch (status) {
      case 'REQUESTED':
      case 'PENDING':
        return Colors.orange;
      case 'ACCEPTED':
        return Colors.blue;
      case 'ARRIVED':
        return Colors.indigo;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        return Colors.green;
      case 'COMPLETED':
        return waitingConfirm ? Colors.amber.shade700 : Colors.redAccent;
      default:
        return Colors.orange;
    }
  }

  String _getStatusLabel(String status, bool waitingConfirm) {
    switch (status) {
      case 'REQUESTED':
        return 'Waiting';
      case 'PENDING':
        return 'Pending';
      case 'ACCEPTED':
        return 'Accepted';
      case 'ARRIVED':
        return 'Arrived';
      case 'ACTIVE':
        return 'In Progress';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'COMPLETED':
        return waitingConfirm ? 'Awaiting confirm' : 'Pending Payment';
      default:
        return status;
    }
  }
}
