import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../repositories/job_credits_repository.dart';
import '../home/active_booking_card.dart';
import '../booking/cancel_booking_screen.dart';
import '../booking/cancel_request_actions.dart';
import '../booking/voice_call_screen.dart';
import '../messages/chat_thread_screen.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/utils/booking_flags.dart';

/// Gixbee 2026 — booking detail: hero status header with progress dots
/// (Requested → Accepted → In progress → Done), glass info cards, and a
/// sticky bottom action bar (message / call / cancel, or accept / decline
/// for the assigned worker). Cancel confirmation runs through gx_sheet.
class BookingDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> booking;

  const BookingDetailScreen({super.key, required this.booking});



  /// Statuses still open to change while this page is on screen — the only
  /// ones worth a live status subscription.
  static const _watchableStatuses = {
    'PENDING',
    'REQUESTED',
    'CUSTOM_REQUESTED',
    'ACCEPTED',
    'CONFIRMED',
    'ARRIVED',
    'ACTIVE',
    'IN_PROGRESS',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledAtRaw = booking['scheduledAt'] != null
        ? (DateTime.tryParse(booking['scheduledAt'].toString()) ?? DateTime.now())
        : (booking['createdAt'] != null
            ? (DateTime.tryParse(booking['createdAt'].toString()) ?? DateTime.now())
            : DateTime.now());
    final scheduledAt = scheduledAtRaw.toLocal();

    final bookingId = booking['id']?.toString() ?? '';
    final snapshotStatus =
        (booking['status'] ?? 'PENDING').toString().toUpperCase();

    // The snapshot is whatever the list held when this page was pushed. Once
    // the pro approves/declines a cancel request the booking moves on without
    // us, so follow the live status instead of the frozen copy.
    final live = bookingId.isNotEmpty &&
            _watchableStatuses.contains(snapshotStatus)
        ? ref.watch(bookingStatusProvider(bookingId)).value
        : null;

    final status =
        live?['status']?.toString().toUpperCase() ?? snapshotStatus;
    final cancelRequested = live != null
        ? bookingFlagTrue(live['cancelRequested'])
        : bookingFlagTrue(
            booking['cancelRequested'] ?? (booking['cancelRequestedAt'] != null),
          );

    final isPaid = bookingFlagTrue(live?['isPaid'] ?? booking['isPaid']) ||
        bookingFlagTrue(live?['customerPaidConfirmed'] ??
            booking['customerPaidConfirmed']) ||
        bookingFlagTrue(
            live?['workerPaidConfirmed'] ?? booking['workerPaidConfirmed']);
    final paymentStatusText = isPaid
        ? 'Paid'
        : (status == 'CANCELLED' || status == 'REJECTED'
            ? 'Cancelled'
            : 'Pending (Post-Service)');
    final paymentStatusColor = isPaid
        ? GixbeeTheme.accentGreen
        : (status == 'CANCELLED' || status == 'REJECTED'
            ? const Color(0xFFEF4444)
            : GixbeeTheme.accentGold);

    final currentUser = ref.watch(currentUserProvider).value;
    final operatorMap = booking['operator'] is Map ? booking['operator'] as Map : null;
    final customerMap = booking['customer'] is Map ? booking['customer'] as Map : null;
    final isAssignedWorker = currentUser?.id != null &&
        currentUser!.id == operatorMap?['id']?.toString();

    // The OTHER party, relative to the viewer — null while a broadcast is
    // still searching (operator unassigned). The old code fell back to
    // booking['customer'], showing customers THEIR OWN name as "vendor"
    // with a hardcoded fake rating.
    final counterpart = isAssignedWorker ? customerMap : operatorMap;
    final counterpartName = counterpart?['name']?.toString();

    final shortId = '#BK-${bookingId.length > 5 ? bookingId.substring(0, 5) : bookingId}';

    final amount = num.tryParse('${booking['totalAmount'] ?? booking['amount'] ?? 0}') ?? 0;
    final serviceName = (booking['skill'] ?? booking['serviceName'] ?? 'General Help').toString();

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        backgroundColor: context.gx.bg,
        elevation: 0,
        title: Text('Booking Details', style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: context.gx.ink),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          children: [
            // Hero section
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.gx.border)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              GixbeeTheme.accentGreen.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.handyman_rounded,
                        size: 34, color: GixbeeTheme.accentGreen),
                  ),
                  const SizedBox(height: 12),
                  Text(serviceName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.gx.ink)),
                  const SizedBox(height: 4),
                  Text(
                    counterpartName != null
                        ? (isAssignedWorker
                            ? 'for $counterpartName'
                            : 'with $counterpartName')
                        : (status == 'REQUESTED'
                            ? 'Finding a pro near you…'
                            : 'Instant request'),
                    style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 10),
                  _buildStatusBadge(context, status),
                ],
              ),
            ),
            
            // Pending cancel request — the worker approves/declines here, the
            // customer can withdraw. Fed from this snapshot so opening a
            // booking never starts a status poll.
            if (bookingId.isNotEmpty &&
                cancelRequested &&
                const {'ACCEPTED', 'ARRIVED', 'ACTIVE', 'IN_PROGRESS'}
                    .contains(status))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CancelRequestActions(
                  bookingId: bookingId,
                  isWorker: isAssignedWorker,
                  cancelRequested: true,
                  onActionCompleted: () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                ),
              ),

            // OTP Section (Only for Customers)
            if (!isAssignedWorker && (status == 'ACCEPTED' || status == 'ACTIVE'))
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status == 'ACCEPTED' &&
                        (live?['arrivalOtp'] ?? booking['arrivalOtp']) != null)
                      _buildOtpCard(
                          context,
                          'Arrival OTP',
                          (live?['arrivalOtp'] ?? booking['arrivalOtp'])
                              .toString(),
                          Icons.meeting_room,
                          context.gx.accent),
                    if (status == 'ACTIVE' && booking['completionOtp'] != null)
                      _buildOtpCard(context, 'Completion OTP', booking['completionOtp'].toString(), Icons.verified, Colors.green),
                  ],
                ),
              ),

            // Details rows
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _buildDetailRow(context, 'Booking ID', shortId, color: context.gx.accentSoft),
                  _buildDetailRow(context, 'Date', DateFormat('d MMM yyyy').format(scheduledAt)),
                  _buildDetailRow(context, 'Time', DateFormat('hh:mm a').format(scheduledAt)),
                  _buildDetailRow(context, 'Total Amount', '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}', color: GixbeeTheme.accentGold, isBig: true),
                  _buildDetailRow(context, 'Payment', paymentStatusText, color: paymentStatusColor),
                  if (isAssignedWorker && bookingId.isNotEmpty)
                    _WorkerCreditsUsedRow(bookingId: bookingId),
                  _buildDetailRow(context, 'Location', booking['serviceLocation'] ?? 'As specified in request'),
                ],
              ),
            ),

            // Counterpart contact section — only when the other party exists.
            // A REQUESTED broadcast has no pro yet: show the searching note
            // instead of a fake vendor card.
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.gx.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAssignedWorker ? 'CUSTOMER' : 'YOUR PRO',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.45),
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 10),
                  if (counterpart != null)
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: context.gx.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.gx.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: context.gx.accentGradient),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              (counterpartName?.isNotEmpty ?? false)
                                  ? counterpartName![0].toUpperCase()
                                  : '?',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.gx.onAccent),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(counterpartName ?? 'Gixbee user',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.gx.ink)),
                                const SizedBox(height: 2),
                                Text(
                                  isAssignedWorker
                                      ? 'Customer for this booking'
                                      : '$serviceName pro',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: context.gx.ink
                                          .withValues(alpha: 0.55)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: GixbeeTheme.accentGreen.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: GixbeeTheme.accentGreen
                                .withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              size: 20, color: GixbeeTheme.accentGreen),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              status == 'REQUESTED'
                                  ? 'Searching for a nearby pro — you\'ll be notified the moment one accepts.'
                                  : 'No pro was assigned to this booking.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: context.gx.ink
                                      .withValues(alpha: 0.7)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Action buttons
                  _buildStickyActionBar(context, ref, status, isAssignedWorker,
                      cancelRequested),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status) {
    Color color;
    switch (status) {
      case 'REQUESTED':
      case 'CUSTOM_REQUESTED':
      case 'PENDING':
        color = GixbeeTheme.accentGold;
        break;
      case 'ACCEPTED':
      case 'CONFIRMED':
      case 'ARRIVED':
        color = GixbeeTheme.accentGreen;
        break;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        color = context.gx.accentSoft;
        break;
      case 'COMPLETED':
        color = GixbeeTheme.accentGreen;
        break;
      case 'CANCELLED':
      case 'REJECTED':
        color = const Color(0xFFEF4444);
        break;
      default:
        color = context.gx.ink.withValues(alpha: 0.58);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {Color? color, bool isBig = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: context.gx.ink.withValues(alpha: 0.5))),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isBig ? 15 : 14,
                fontWeight: FontWeight.w600,
                color: color ?? context.gx.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpCard(BuildContext context, String title, String otp, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: context.gx.ink.withValues(alpha: 0.58), fontSize: 12)),
                const SizedBox(height: 4),
                Text('Share this code with the worker', style: TextStyle(fontSize: 11, color: context.gx.ink)),
              ],
            ),
          ),
          Text(
            otp,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Action Bar Buttons
  Widget _buildStickyActionBar(BuildContext context, WidgetRef ref,
      String status, bool isAssignedWorker, bool cancelRequested) {
    final counterpart = isAssignedWorker ? (booking['customer'] ?? {}) : (booking['operator'] ?? {});
    final counterpartId = counterpart['id']?.toString();
    final counterpartName = (counterpart['name'] ?? 'Gixbee user').toString();
    // User entity serializes as phoneNumber; tolerate legacy `phone` too.
    String? counterpartPhone = (counterpart['phoneNumber'] ?? counterpart['phone'])
        ?.toString()
        .trim();
    if (counterpartPhone != null && counterpartPhone.isEmpty) {
      counterpartPhone = null;
    }
    if (isAssignedWorker && counterpartPhone == null) {
      final onSite = booking['onSiteContact'];
      final onSitePhone =
          onSite is Map ? onSite['phone']?.toString().trim() : null;
      if (onSitePhone != null && onSitePhone.isNotEmpty) {
        counterpartPhone = onSitePhone;
      }
    }

    const cancellable = {'PENDING', 'REQUESTED', 'ACCEPTED', 'CONFIRMED'};
    // A pending request already owns the cancel flow above (withdraw /
    // approve) — a second entry point here would re-cancel a settled booking.
    final canCancel =
        !isAssignedWorker && !cancelRequested && cancellable.contains(status);
    final canMessage = counterpartId != null && counterpartId.isNotEmpty;
    final showAcceptDecline = status == 'REQUESTED' && isAssignedWorker;

    if (!canMessage && !canCancel && !showAcceptDecline) return const SizedBox.shrink();

    if (showAcceptDecline) {
      return Row(
        children: [
          Expanded(
            child: GxButton(
              label: 'Decline',
              filled: false,
              accent: Colors.red,
              onTap: () async {
                try {
                  await ref
                      .read(bookingRepositoryProvider)
                      .rejectBooking(booking['id'].toString());
                  ref.invalidate(myBookingsProvider);
                  ref.invalidate(activeBookingProvider);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) showGxSnack(context, 'Failed to decline: $e', type: GxSnackType.error);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GxButton(
              label: 'Accept Job',
              gradient: const [Colors.green, Colors.green],
              accent: Colors.green,
              onTap: () async {
                try {
                  await ref.read(bookingRepositoryProvider).acceptBooking(booking['id']);
                  ref.invalidate(myBookingsProvider);
                  ref.invalidate(activeBookingProvider);
                  if (context.mounted) {
                    Navigator.pop(context);
                    showGxSnack(context, 'Job Accepted!', type: GxSnackType.success);
                  }
                } catch (e) {
                  if (context.mounted) showGxSnack(context, 'Failed to accept: $e', type: GxSnackType.error);
                }
              },
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        if (canMessage)
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatThreadScreen(
                    otherUserId: counterpartId,
                    otherUserName: counterpartName,
                    bookingId: booking['id']?.toString(),
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: context.gx.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text('Message', style: TextStyle(color: context.gx.onAccent, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        if (canMessage) const SizedBox(width: 8),
        if (canMessage)
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final bookingId = booking['id']?.toString();
                if (bookingId == null || bookingId.isEmpty) {
                  showGxSnack(context, 'Booking not available');
                  return;
                }
                final me = ref.read(currentUserProvider).value;
                final callerName =
                    (me?.name?.trim().isNotEmpty == true)
                        ? me!.name!.trim()
                        : 'Gixbee user';
                await VoiceCallScreen.startOutgoing(
                  context,
                  bookingId: bookingId,
                  callerName: callerName,
                  peerName: counterpartName,
                  fallbackPhone: counterpartPhone,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: context.gx.ink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text('Call', style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        if (canCancel) const SizedBox(width: 8),
        if (canCancel)
          Expanded(
            child: GestureDetector(
              onTap: () => _confirmCancel(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.red.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: const Text('Cancel',
                    style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ),
          ),
      ],
    );
  }

  void _confirmCancel(BuildContext context) {
    showGxSheet(
      context,
      title: 'Cancel this booking?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Refunds follow the cancellation policy based on how close to the start time you cancel.',
            style: TextStyle(color: context.gx.ink.withValues(alpha: 0.58), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'Keep booking',
                  filled: false,
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GxButton(
                  label: 'Cancel booking',
                  gradient: const [Colors.red, Colors.red],
                  accent: Colors.red,
                  onTap: () {
                    Navigator.pop(context); // close the sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CancelBookingScreen(
                          bookingId: booking['id'].toString(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

/// Worker-only row: pack credits spent on accept (from credit_transactions).
class _WorkerCreditsUsedRow extends ConsumerStatefulWidget {
  final String bookingId;

  const _WorkerCreditsUsedRow({required this.bookingId});

  @override
  ConsumerState<_WorkerCreditsUsedRow> createState() =>
      _WorkerCreditsUsedRowState();
}

class _WorkerCreditsUsedRowState extends ConsumerState<_WorkerCreditsUsedRow> {
  int? _used;
  int _refunded = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final info = await ref
        .read(jobCreditsRepositoryProvider)
        .getBookingCreditUsage(widget.bookingId);
    if (!mounted) return;
    setState(() {
      _used = (info['creditsUsed'] as num?)?.toInt() ?? 0;
      _refunded = (info['creditsRefunded'] as num?)?.toInt() ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_used == null || _used == 0) {
      // Still loading, or older booking with no credit tx (don't show 0).
      if (_used == null) return const SizedBox.shrink();
      return const SizedBox.shrink();
    }
    final used = _used!;
    final value = _refunded > 0
        ? '$used (refunded)'
        : '$used credit${used == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Credits used',
            style: TextStyle(
              fontSize: 14,
              color: context.gx.ink.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _refunded > 0
                    ? GixbeeTheme.accentTeal
                    : GixbeeTheme.accentGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

