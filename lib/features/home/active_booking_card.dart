import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/auth_repository.dart';
import '../booking/arrival_otp_screen.dart';
import '../booking/completion_otp_screen.dart';
import '../jobs/booking_detail_screen.dart';
import '../../shared/widgets/glass_container.dart';

class ActiveBookingCard extends ConsumerWidget {
  const ActiveBookingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        
        // Use a StreamProvider or FutureProvider for bookings would be better,
        // but for now we'll fetch them directly or use a refreshable provider.
        return FutureBuilder<List<dynamic>>(
          future: ref.read(bookingRepositoryProvider).getMyBookings(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();

            // Find the first active booking
            final activeStatuses = ['ACCEPTED', 'ARRIVED', 'ACTIVE', 'IN_PROGRESS', 'CONFIRMED'];
            final activeBooking = snapshot.data!.firstWhere(
              (b) => activeStatuses.contains((b['status'] ?? '').toString().toUpperCase()),
              orElse: () => null,
            );

            if (activeBooking == null) return const SizedBox.shrink();

            final bStatus = (activeBooking['status'] ?? '').toString().toUpperCase();
            final isOperator = user.id == (activeBooking['operator']?['id'] ?? activeBooking['operator']);
            final scheduledAt = activeBooking['scheduledAt'] != null
                ? DateTime.parse(activeBooking['scheduledAt'])
                : DateTime.now();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onTap: () {
                   if (bStatus == 'ACCEPTED' || bStatus == 'ARRIVED') {
                     Navigator.push(
                       context,
                       MaterialPageRoute(
                         builder: (_) => ArrivalOtpScreen(
                           bookingId: activeBooking['id'],
                           workerName: activeBooking['operator']?['name'] ?? 'Worker',
                           arrivalOtp: activeBooking['arrivalOtp'] ?? '',
                           isWorker: isOperator,
                         ),
                       ),
                     );
                   } else if (bStatus == 'ACTIVE' || bStatus == 'IN_PROGRESS') {
                     Navigator.push(
                       context,
                       MaterialPageRoute(
                         builder: (_) => CompletionOtpScreen(
                           bookingId: activeBooking['id'],
                           workerName: activeBooking['operator']?['name'] ?? 'Worker',
                           isWorker: isOperator,
                         ),
                       ),
                     );
                   } else {
                     Navigator.push(
                       context,
                       MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: activeBooking)),
                     );
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
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.run_circle_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOperator ? 'Active Job' : 'Current Booking',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              '${activeBooking['serviceName'] ?? 'General Help'} • ${DateFormat('hh:mm a').format(scheduledAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             decoration: BoxDecoration(
                               color: _getStatusColor(bStatus).withValues(alpha: 0.1),
                               borderRadius: BorderRadius.circular(12),
                             ),
                             child: Text(
                               bStatus,
                               style: TextStyle(
                                 fontSize: 10,
                                 fontWeight: FontWeight.bold,
                                 color: _getStatusColor(bStatus),
                               ),
                             ),
                           ),
                           const SizedBox(height: 4),
                           const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'ACCEPTED') return Colors.blue;
    if (status == 'ACTIVE' || status == 'IN_PROGRESS') return Colors.green;
    return Colors.orange;
  }
}
