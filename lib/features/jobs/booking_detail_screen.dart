import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';

class BookingDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> booking;

  const BookingDetailScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final scheduledAt = booking['scheduledAt'] != null
        ? DateTime.parse(booking['scheduledAt'])
        : DateTime.now();
    final status = (booking['status'] ?? 'PENDING').toString().toUpperCase();
    
    final displayUser = booking['operator'] ?? booking['customer'] ?? {};
    final userName = displayUser['name'] ?? 'Worker';
    final userImg = displayUser['profileImageUrl'] ?? 'https://i.pravatar.cc/150?u=${booking['id']}';
    
    final currentUser = ref.watch(currentUserProvider).value;
    final isAssignedWorker = currentUser?.id == booking['operator']?['id'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Support flow coming soon')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            _buildStatusCard(context, status),
            const SizedBox(height: 24),

            // User Info Section
            Text(
              status == 'COMPLETED' ? 'Professional' : 'Assigned Professional',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            GlassContainer(
              padding: const EdgeInsets.all(12),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 28,
                  backgroundImage: NetworkImage(userImg),
                ),
                title: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Verified Professional'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.phone_outlined, color: Colors.green),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // OTP Section (Only for Customers)
            if (!isAssignedWorker && (status == 'ACCEPTED' || status == 'ACTIVE'))
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Security Pin',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (status == 'ACCEPTED' && booking['arrivalOtp'] != null)
                    _buildOtpCard(context, 'Arrival OTP', booking['arrivalOtp'].toString(), Icons.meeting_room, Colors.orange),
                  if (status == 'ACTIVE' && booking['completionOtp'] != null)
                    _buildOtpCard(context, 'Completion OTP', booking['completionOtp'].toString(), Icons.verified, Colors.green),
                  const SizedBox(height: 24),
                ],
              ),

            // Service Details
            const Text(
              'Service Summary',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(context, Icons.handyman_outlined, 'Service', booking['serviceName'] ?? 'General Help'),
            _buildDetailRow(context, Icons.calendar_today, 'Date', DateFormat('EEEE, MMM d').format(scheduledAt)),
            _buildDetailRow(context, Icons.access_time, 'Time', DateFormat('hh:mm a').format(scheduledAt)),
            _buildDetailRow(context, Icons.location_on_outlined, 'Location', booking['serviceLocation'] ?? 'As specified in request'),
            
            const Divider(height: 48),

            // Payment Section
            const Text(
              'Payment Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Service Fee'),
                Text('₹${booking['amount'] ?? 0}'),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Platform Fee'),
                Text('₹0'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '₹${booking['amount'] ?? 0}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 20, 
                    color: colorScheme.primary
                  )
                ),
              ],
            ),

            const SizedBox(height: 60),

            // Actions for REQUESTED Booking (Worker Fallback)
            if (status == 'REQUESTED' && isAssignedWorker)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await ref.read(bookingRepositoryProvider).updateBookingStatus(booking['id'], 'REJECTED');
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to decline: $e')));
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await ref.read(bookingRepositoryProvider).acceptBooking(booking['id']);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job Accepted!')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Accept Job', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),

            // Actions for Active Booking
            if (status == 'ACTIVE')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Track Live Location'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, String status) {
    final color = _getStatusColor(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(_getStatusIcon(status), color: color, size: 40),
          const SizedBox(height: 12),
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            'Ref ID: ${booking['id']?.toString().substring(0, 8).toUpperCase()}',
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'REQUESTED':
      case 'CUSTOM_REQUESTED':
        return Colors.orange;
      case 'PENDING':
      case 'ACCEPTED':
      case 'CONFIRMED':
      case 'ACTIVE':
        return Colors.blue;
      case 'IN_PROGRESS':
        return Colors.indigo;
      case 'COMPLETED': return Colors.green;
      case 'CANCELLED': 
      case 'REJECTED':
        return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'REQUESTED':
      case 'CUSTOM_REQUESTED':
        return Icons.pending_actions;
      case 'PENDING':
      case 'ACCEPTED':
      case 'CONFIRMED':
      case 'ACTIVE': 
        return Icons.directions_run;
      case 'IN_PROGRESS':
        return Icons.handyman;
      case 'COMPLETED': return Icons.verified;
      case 'CANCELLED': 
      case 'REJECTED': 
        return Icons.cancel;
      default: return Icons.info;
    }
  }

  Widget _buildOtpCard(BuildContext context, String title, String otp, IconData icon, Color color) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
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
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('Share this code when the worker asks for it', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Text(
            otp,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
