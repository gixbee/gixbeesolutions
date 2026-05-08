import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_strings.dart';
import 'features/home/home_screen.dart';
import 'features/map/worker_directory_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/jobs/my_bookings_screen.dart';
import 'features/booking/incoming_job_screen.dart';
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

  /// Tracks booking IDs already shown — prevents duplicate popups from
  /// FCM foreground + socket + HTTP poll all firing for the same booking.
  final Set<String> _shownBookingIds = {};

  final List<Widget> _screens = [
    const HomeScreen(),
    const MyBookingsScreen(),
    const WorkerDirectoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback so ref is safe to use after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSocket();
      _initNotifications();
      _maybeStartWorkerPoll();
    });
  }

  @override
  void dispose() {
    _pendingPollTimer?.cancel();
    super.dispose();
  }

  // ── Notification Initialization ─────────────────────────────────────────

  Future<void> _initNotifications() async {
    final notifService = ref.read(notificationServiceProvider);

    // STEP 1 — Initialize FCM listeners, Android channel, permission prompt.
    // This is called ONCE here. The _initialized guard in NotificationService
    // ensures it's a no-op if somehow called again.
    // Note: FirebaseMessaging.onBackgroundMessage was already registered in
    // main() before runApp() — NotificationService.initialize() does NOT
    // register it again.
    await notifService.initialize();

    // STEP 2 — Sync FCM token with backend on every app start.
    // If the token was rotated by FCM while the app was killed, this ensures
    // the backend always has the current token.
    await _syncFcmToken(notifService);

    // STEP 3 — Listen for token rotation by FCM (happens ~monthly)
    notifService.onTokenRefresh((newToken) async {
      try {
        await ref.read(authRepositoryProvider).registerFcmToken(newToken);
        debugPrint('[FCM] Token refreshed and re-registered with backend');
      } catch (e) {
        debugPrint('[FCM] Token refresh registration failed: $e');
      }
    });

    // STEP 4 — Foreground messages (app is open)
    notifService.addForegroundListener((RemoteMessage message) {
      _handleFcmMessage(message);
    });

    // STEP 5 — Notification tap (app was in background)
    notifService.addClickListener((RemoteMessage message) {
      _handleNotificationTap(message);
    });

    // STEP 6 — App was killed and launched via notification tap
    // Must be called after initialize() to be reliable
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialMessage = await notifService.getInitialMessage();
      if (initialMessage != null && mounted) {
        _handleNotificationTap(initialMessage);
      }
    });
  }

  Future<void> _syncFcmToken(NotificationService notifService) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final token = await notifService.getDeviceToken();
        if (token == null) return;
        await ref.read(authRepositoryProvider).registerFcmToken(token);
        debugPrint('[FCM] Token synced on app start (attempt $attempt)');
        return;
      } catch (e) {
        debugPrint('[FCM] Token sync attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
  }

  // ── Socket ──────────────────────────────────────────────────────────────

  Future<void> _initSocket() async {
    final token = await ref.read(authTokenServiceProvider).getToken();
    if (token == null) return;

    final socketService = ref.read(socketServiceProvider);
    socketService.connect(token);

    socketService.notifications.listen((data) {
      final event = data['_event'] as String?;
      final id = data['id'] as String?;

      if (event == 'new_booking_request') {
        if (id != null && !_shownBookingIds.contains(id)) {
          _shownBookingIds.add(id);
          _showIncomingJobScreen(data);
        }
      } else if (event == 'booking_accepted') {
        if (mounted) setState(() => _currentIndex = 1);
      }
    });
  }

  // ── Worker Poll (FCM + Socket fallback) ─────────────────────────────────

  Future<void> _maybeStartWorkerPoll() async {
    // await .future to get the resolved value — .value is null at initState time
    final user = await ref.read(currentUserProvider.future);
    if (user?.isWorker == true) {
      _startPendingBookingPoll();
    }
  }

  void _startPendingBookingPoll() {
    _pendingPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final pending =
            await ref.read(bookingRepositoryProvider).getPendingBookings();
        for (final booking in pending) {
          final id = booking['id'] as String?;
          if (id != null && !_shownBookingIds.contains(id)) {
            _shownBookingIds.add(id);
            _showIncomingJobScreen(booking);
          }
        }
      } catch (_) {
        // Silent — FCM is the primary delivery channel
      }
    });
  }

  // ── FCM Message Handlers ─────────────────────────────────────────────────

  void _handleFcmMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;
    final bookingId = message.data['bookingId'] as String?;

    if (type == 'new_booking') {
      // Dedup: skip if already shown via socket or HTTP poll
      if (bookingId != null && _shownBookingIds.contains(bookingId)) {
        debugPrint('[FCM] Skipping duplicate popup for booking: $bookingId');
        return;
      }
      if (bookingId != null) _shownBookingIds.add(bookingId);

      _showIncomingJobScreen({
        'id': bookingId,
        'skill': message.data['skill'] ?? 'General Help',
        'customer_name':
            message.notification?.title ?? AppStrings.fcmDefaultTitle,
        'serviceLocation': message.data['serviceLocation'] ?? '',
        'amount':
            double.tryParse(message.data['amount'] ?? '0') ?? 0.0,
      });
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'] as String?;
    if (!mounted) return;
    if (type == 'new_booking' || type == 'booking_accepted') {
      setState(() => _currentIndex = 1); // go to Bookings tab
    }
  }

  // ── Incoming Job Screen ──────────────────────────────────────────────────

  void _showIncomingJobScreen(Map<String, dynamic> bookingData) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingJobScreen(bookingData: bookingData),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

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
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Bookings',
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
