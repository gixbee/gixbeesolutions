import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_strings.dart';
import 'features/home/home_screen.dart';
import 'features/map/worker_directory_screen.dart';
import 'features/profile/profile_screen.dart';
import 'repositories/auth_repository.dart';
import 'repositories/booking_repository.dart';
import 'services/auth_token_service.dart';
import 'services/notification_service.dart';
import 'services/socket_service.dart';
import 'shared/widgets/dribbble_background.dart';

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});

  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper> {
  int _currentIndex = 0;
  Timer? _pendingPollTimer;
  final Set<String> _shownBookingIds = {};

  final List<Widget> _screens = const [
    HomeScreen(),
    WorkerDirectoryScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initSocket();
    _initNotifications();
    _startPendingBookingPoll();
  }

  @override
  void dispose() {
    _pendingPollTimer?.cancel();
    super.dispose();
  }

  // ── Pending Booking Poll (FCM fallback) ─────────────────

  void _startPendingBookingPoll() {
    _pendingPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final pending = await ref.read(bookingRepositoryProvider).getPendingBookings();
        for (final booking in pending) {
          final id = booking['id'] as String?;
          if (id != null && !_shownBookingIds.contains(id)) {
            _shownBookingIds.add(id);
            _showJobRequestPopup(
              'New Job Request',
              '${booking['customer']?['name'] ?? 'A customer'} needs ${booking['skill'] ?? 'your services'}',
              id,
            );
          }
        }
      } catch (_) {}
    });
  }

  // ── Socket ───────────────────────────────────────────────

  Future<void> _initSocket() async {
    final token = await ref.read(authTokenServiceProvider).getToken();
    if (token != null) {
      ref.read(socketServiceProvider).connect(token);
    }
  }

  // ── FCM Notifications ────────────────────────────────────

  Future<void> _initNotifications() async {
    final notifService = ref.read(notificationServiceProvider);

    // Token registration on startup
    notifService.getDeviceToken().then((token) async {
      if (token != null) {
        debugPrint('[FCM] Registering token on startup');
        await ref.read(authRepositoryProvider).registerFcmToken(token);
      }
    });

    // Token refresh — re-register with backend when FCM rotates the token
    notifService.onTokenRefresh((newToken) async {
      debugPrint('[FCM] Token refreshed — re-registering');
      await ref.read(authRepositoryProvider).registerFcmToken(newToken);
    });

    // Foreground — app is open, show in-app dialog for booking events
    notifService.addForegroundListener((RemoteMessage message) {
      _handleMessage(message);
    });

    // Background tap — user tapped notification while app was backgrounded
    notifService.addClickListener((RemoteMessage message) {
      _handleNotificationTap(message);
    });

    // Killed state tap — app was closed, user tapped notification to open it
    final initialMessage = await notifService.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Handles the data payload from any FCM message.
  void _handleMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;

    if (type == 'new_booking') {
      _showJobRequestPopup(
        message.notification?.title ?? AppStrings.fcmDefaultTitle,
        message.notification?.body ?? AppStrings.fcmDefaultBody,
        message.data['bookingId'] as String?,
      );
    }
  }

  /// Handles navigation when user taps a notification.
  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'] as String?;
    debugPrint('[FCM] Notification tapped — type: $type');

    if (type == 'new_booking') {
      // Navigate to bookings or home
      setState(() => _currentIndex = 0);
    }
  }

  // ── Job Request Popup ────────────────────────────────────

  void _showJobRequestPopup(String title, String body, String? bookingId) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Decline', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (bookingId == null) return;
              try {
                await ref
                    .read(bookingRepositoryProvider)
                    .acceptBooking(bookingId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Job Accepted! Head to the location.'),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('[Booking] Accept failed: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to accept: $e')),
                  );
                }
              }
            },
            child: const Text(
              'Accept Job',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DribbbleBackground(
        child: _screens[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_searching),
            selectedIcon: Icon(Icons.my_location),
            label: 'Nearby',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
