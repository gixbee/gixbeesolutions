import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/booking_repository.dart';

/// Simple in-app notification model
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type; // booking_accepted, new_booking, job_completed, etc.
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.data,
  });
}

/// Provider that builds notifications from booking history
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final bookings = await ref.watch(myBookingsProvider.future);
  final notifications = <AppNotification>[];

  for (final b in bookings) {
    final status = (b['status'] ?? '').toString().toUpperCase();
    final id = b['id']?.toString() ?? '';
    final operatorName = b['operator']?['name'] ?? 'Worker';
    final customerName = b['customer']?['name'] ?? 'Customer';
    final skill = b['skill'] ?? b['serviceName'] ?? 'Service';
    final updatedAt = b['updatedAt'] != null
        ? DateTime.tryParse(b['updatedAt'].toString()) ?? DateTime.now()
        : DateTime.now();

    switch (status) {
      case 'REQUESTED':
        notifications.add(AppNotification(
          id: '${id}_requested',
          title: 'New Booking Request',
          body: '$customerName needs help with $skill',
          type: 'new_booking',
          timestamp: updatedAt,
          data: b,
        ));
        break;
      case 'ACCEPTED':
        notifications.add(AppNotification(
          id: '${id}_accepted',
          title: 'Booking Accepted',
          body: '$operatorName has accepted your request for $skill',
          type: 'booking_accepted',
          timestamp: updatedAt,
          data: b,
        ));
        break;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        notifications.add(AppNotification(
          id: '${id}_active',
          title: 'Job In Progress',
          body: '$operatorName has arrived and started the job',
          type: 'job_started',
          timestamp: updatedAt,
          data: b,
        ));
        break;
      case 'COMPLETED':
        notifications.add(AppNotification(
          id: '${id}_completed',
          title: 'Job Completed ✅',
          body: '$skill with $operatorName has been completed',
          type: 'job_completed',
          timestamp: updatedAt,
          data: b,
        ));
        break;
      case 'CANCELLED':
      case 'REJECTED':
        notifications.add(AppNotification(
          id: '${id}_cancelled',
          title: 'Booking Cancelled',
          body: 'Your $skill booking has been cancelled',
          type: 'cancelled',
          timestamp: updatedAt,
          data: b,
        ));
        break;
    }
  }

  // Sort newest first
  notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return notifications;
});

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // Track dismissed notification IDs locally
  final Set<String> _dismissedIds = {};

  @override
  Widget build(BuildContext context) {
    final notifAsync = ref.watch(notificationsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_dismissedIds.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _dismissedIds.clear());
                ref.invalidate(notificationsProvider);
              },
              child: const Text('Restore All'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _dismissedIds.clear());
              ref.invalidate(notificationsProvider);
            },
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (notifications) {
          // Filter out dismissed notifications
          final visible = notifications
              .where((n) => !_dismissedIds.contains(n.id))
              .toList();

          if (visible.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 72, color: Colors.grey.shade600),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _dismissedIds.isNotEmpty
                        ? 'All notifications cleared'
                        : 'Your booking updates will appear here',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final notif = visible[index];
              return Dismissible(
                key: Key(notif.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) {
                  setState(() => _dismissedIds.add(notif.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Notification cleared'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () {
                          setState(() => _dismissedIds.remove(notif.id));
                        },
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.red),
                ),
                child: _buildNotificationTile(context, notif, colorScheme),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationTile(BuildContext context, AppNotification notif, ColorScheme cs) {
    final icon = _getIcon(notif.type);
    final iconColor = _getColor(notif.type);
    final timeAgo = _formatTimeAgo(notif.timestamp);

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notif.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'new_booking': return Icons.add_circle_outline;
      case 'booking_accepted': return Icons.check_circle_outline;
      case 'job_started': return Icons.play_circle_outline;
      case 'job_completed': return Icons.verified_outlined;
      case 'cancelled': return Icons.cancel_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'new_booking': return Colors.orange;
      case 'booking_accepted': return Colors.blue;
      case 'job_started': return Colors.green;
      case 'job_completed': return Colors.teal;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }
}
