import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/booking_repository.dart';
import 'booking_detail_screen.dart';
import '../../repositories/auth_repository.dart';
import '../booking/arrival_otp_screen.dart';
import '../booking/completion_otp_screen.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(myBookingsProvider),
            ),
          ],
        ),
        body: bookingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (bookings) => TabBarView(
            children: [
              _buildBookingList(context, ref, bookings, 'ACTIVE'),
              _buildBookingList(context, ref, bookings, 'COMPLETED'),
              _buildBookingList(context, ref, bookings, 'CANCELLED'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingList(BuildContext context, WidgetRef ref, List<dynamic> bookings, String tab) {
    final filtered = bookings.where((b) {
      final bStatus = (b['status'] ?? '').toString().toUpperCase();
      if (tab == 'ACTIVE') {
        return ['REQUESTED', 'CUSTOM_REQUESTED', 'PENDING', 'ACCEPTED', 'CONFIRMED', 'ACTIVE', 'IN_PROGRESS'].contains(bStatus);
      } else if (tab == 'CANCELLED') {
        return bStatus == 'CANCELLED' || bStatus == 'REJECTED';
      } else {
        return bStatus == tab;
      }
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'No ${tab.toLowerCase()} bookings found',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final booking = filtered[index];
        final scheduledAt = booking['scheduledAt'] != null
            ? DateTime.parse(booking['scheduledAt'])
            : DateTime.now();
        
        // Identify if I'm the worker or the customer
        // (Just a simple display logic, for production we'd use roles)
        final displayUser = booking['operator'] ?? booking['customer'] ?? {};
        final userName = displayUser['name'] ?? 'Booking #${booking['id']?.toString().substring(0, 5)}';
        final userImg = displayUser['profileImageUrl'] ?? 'https://i.pravatar.cc/150?u=${booking['id']}';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: NetworkImage(userImg),
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            booking['serviceName'] ?? 'General Service',
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
                    _buildStatusBadge((booking['status'] ?? 'PENDING').toString().toUpperCase()),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date & Time',
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          DateFormat('MMM d, yyyy - hh:mm a').format(scheduledAt),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          tab == 'ACTIVE' ? 'Estimated' : 'Total Paid',
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '₹${booking['amount'] ?? 0}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingDetailScreen(booking: booking),
                            ),
                          );
                          ref.invalidate(myBookingsProvider);
                        },
                        child: const Text('Details'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final user = ref.read(currentUserProvider).value;
                          final isOperator = user?.id == (booking['operator']?['id'] ?? booking['operator']);
                          
                          return ElevatedButton(
                            onPressed: () async {
                               final bStatus = (booking['status'] ?? '').toString().toUpperCase();
                               
                               if (bStatus == 'ACCEPTED' || bStatus == 'ARRIVED') {
                                 final otp = booking['arrivalOtp']?.toString();
                                 if (otp == null || otp.isEmpty) {
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     const SnackBar(content: Text('Verification code is not generated yet. Please wait...')),
                                   );
                                   return;
                                 }
                                 await Navigator.push(
                                   context,
                                   MaterialPageRoute(
                                     builder: (_) => ArrivalOtpScreen(
                                       bookingId: booking['id'],
                                       workerName: booking['operator']?['name'] ?? 'Worker',
                                       arrivalOtp: otp,
                                       isWorker: isOperator,
                                     ),
                                   ),
                                 );
                               } else if (bStatus == 'ACTIVE' || bStatus == 'IN_PROGRESS') {
                                 await Navigator.push(
                                   context,
                                   MaterialPageRoute(
                                     builder: (_) => CompletionOtpScreen(
                                       bookingId: booking['id'],
                                       workerName: booking['operator']?['name'] ?? 'Worker',
                                       isWorker: isOperator,
                                     ),
                                   ),
                                 );
                               } else {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: booking)),
                                  );
                               }
                               // Refresh bookings after returning from any sub-screen
                               ref.invalidate(myBookingsProvider);
                            },
                            child: Text(tab == 'ACTIVE' ? 'Open Tracker' : 'Rebook'),
                          );
                        }
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toUpperCase()) {
      case 'REQUESTED':
        color = Colors.orange;
        break;
      case 'ACCEPTED':
        color = Colors.blue;
        break;
      case 'IN_PROGRESS':
        color = Colors.indigo;
        break;
      case 'COMPLETED':
        color = Colors.green;
        break;
      case 'CANCELLED':
      case 'REJECTED':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

