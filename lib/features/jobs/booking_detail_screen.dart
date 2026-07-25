import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../home/active_booking_card.dart';
import '../booking/cancel_booking_screen.dart';
import '../messages/chat_thread_screen.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gixbee 2026 — booking detail: hero status header with progress dots
/// (Requested → Accepted → In progress → Done), glass info cards, and a
/// sticky bottom action bar (message / call / cancel, or accept / decline
/// for the assigned worker). Cancel confirmation runs through gx_sheet.
class BookingDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> booking;

  const BookingDetailScreen({super.key, required this.booking});



  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledAt = booking['scheduledAt'] != null
        ? DateTime.parse(booking['scheduledAt'])
        : DateTime.now();
    final status = (booking['status'] ?? 'PENDING').toString().toUpperCase();

    final displayUser = booking['operator'] ?? booking['customer'] ?? {};
    final userName = (displayUser['name'] ?? 'Worker').toString();
    final bookingId = booking['id']?.toString() ?? '';
    final shortId = '#BK-${bookingId.length > 5 ? bookingId.substring(0, 5) : bookingId}';
    
    final amount = num.tryParse('${booking['totalAmount'] ?? booking['amount'] ?? 0}') ?? 0;
    final serviceName = (booking['skill'] ?? booking['serviceName'] ?? 'General Help').toString();

    final currentUser = ref.watch(currentUserProvider).value;
    final isAssignedWorker = currentUser?.id == booking['operator']?['id'];

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
                  const Text('🛠️', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 10),
                  Text(serviceName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.gx.ink)),
                  const SizedBox(height: 4),
                  Text(userName, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
                  const SizedBox(height: 10),
                  _buildStatusBadge(status),
                ],
              ),
            ),
            
            // OTP Section (Only for Customers)
            if (!isAssignedWorker && (status == 'ACCEPTED' || status == 'ACTIVE'))
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status == 'ACCEPTED' && booking['arrivalOtp'] != null)
                      _buildOtpCard(context, 'Arrival OTP', booking['arrivalOtp'].toString(), Icons.meeting_room, GixbeeTheme.accentPurple),
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
                  _buildDetailRow(context, 'Booking ID', shortId, color: GixbeeTheme.accentViolet),
                  _buildDetailRow(context, 'Date', DateFormat('d MMM yyyy').format(scheduledAt)),
                  _buildDetailRow(context, 'Time', DateFormat('hh:mm a').format(scheduledAt)),
                  _buildDetailRow(context, 'Total Amount', '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}', color: GixbeeTheme.accentGold, isBig: true),
                  _buildDetailRow(context, 'Payment', 'Paid', color: GixbeeTheme.accentGreen),
                  _buildDetailRow(context, 'Location', booking['serviceLocation'] ?? 'As specified in request'),
                ],
              ),
            ),

            // Counterpart contact section
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
                    isAssignedWorker ? 'CUSTOMER CONTACT' : 'VENDOR CONTACT',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2A2A3E), letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 10),
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
                            gradient: const LinearGradient(colors: GixbeeTheme.purpleGradient),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.gx.onAccent),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(userName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.gx.ink)),
                              const SizedBox(height: 2),
                              const Text('Verified · 4.8 ⭐', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Action buttons
                  _buildStickyActionBar(context, ref, status, isAssignedWorker),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
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
        color = GixbeeTheme.accentViolet;
        break;
      case 'COMPLETED':
        color = GixbeeTheme.accentGreen;
        break;
      case 'CANCELLED':
      case 'REJECTED':
        color = const Color(0xFFEF4444);
        break;
      default:
        color = GixbeeTheme.textMed;
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF888888))),
          Text(
            value,
            style: TextStyle(
              fontSize: isBig ? 15 : 14,
              fontWeight: FontWeight.w600,
              color: color ?? context.gx.ink,
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
                Text(title, style: const TextStyle(color: GixbeeTheme.textMed, fontSize: 12)),
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
  Widget _buildStickyActionBar(BuildContext context, WidgetRef ref, String status, bool isAssignedWorker) {
    final counterpart = isAssignedWorker ? (booking['customer'] ?? {}) : (booking['operator'] ?? {});
    final counterpartId = counterpart['id']?.toString();
    final counterpartName = (counterpart['name'] ?? 'Gixbee user').toString();
    final counterpartPhone = counterpart['phone']?.toString();

    const cancellable = {'PENDING', 'REQUESTED', 'ACCEPTED', 'CONFIRMED'};
    final canCancel = !isAssignedWorker && cancellable.contains(status);
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
                  color: GixbeeTheme.accentViolet,
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
                if (counterpartPhone == null || counterpartPhone.isEmpty) {
                  showGxSnack(context, 'Phone number not available');
                  return;
                }
                final uri = Uri.parse('tel:$counterpartPhone');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
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
          GestureDetector(
            onTap: () => _confirmCancel(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, color: Colors.red, size: 20),
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
          const Text(
            'Refunds follow the cancellation policy based on how close to the start time you cancel.',
            style: TextStyle(color: GixbeeTheme.textMed, fontSize: 13, height: 1.5),
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
