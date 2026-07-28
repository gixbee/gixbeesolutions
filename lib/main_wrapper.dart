import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/debug_log_service.dart';
import 'services/location_bootstrap.dart';
import 'core/config/app_strings.dart';
import 'core/config/app_config.dart';
import 'theme.dart';
import 'features/home/home_screen.dart';
import 'features/home/active_booking_card.dart';
import 'features/messages/messages_list_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/jobs/my_bookings_screen.dart';
import 'features/booking/incoming_job_screen.dart';
import 'features/jobs/pro_skill_provider.dart';
import 'features/worker/go_live_screen.dart';
import 'repositories/worker_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/booking_repository.dart';
import 'services/auth_token_service.dart';
import 'services/notification_service.dart';
import 'services/socket_service.dart';
import 'shared/widgets/dribbble_background.dart';
import 'core/main_tab_provider.dart';

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});

  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _pendingPollTimer;
  StreamSubscription? _notifSub; // AUDIT FIX: was leaked (never cancelled)
  bool _pollWasRunning = false;

  /// Tracks booking IDs already shown — prevents duplicate popups from
  /// FCM foreground + socket + HTTP poll all firing for the same booking.
  final Set<String> _shownBookingIds = {};

  /// Worker declined / dismissed these — never re-open via poll/FCM/socket
  /// for the rest of this session (backend also drops Redis pending).
  final Set<String> _declinedBookingIds = {};

  /// True while IncomingJobScreen is on the navigator stack — blocks stacked
  /// duplicate pushes from poll + FCM racing.
  bool _incomingJobOpen = false;

  /// Body screens, indexed by [_currentIndex]. Go Live is NOT a body tab —
  /// it is the center FAB that pushes [GoLiveScreen] as an overlay, matching
  /// the mockup. Tab order: Home · Bookings · Messages · Profile.
  final List<Widget> _screens = [
    const HomeScreen(),
    const MyBookingsScreen(),
    const MessagesListScreen(),
    const ProfileScreen(),
  ];

  void _goToTab(int index) {
    ref.read(mainTabIndexProvider.notifier).state = index;
    if (_currentIndex != index) setState(() => _currentIndex = index);
  }

  void _openGoLive() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoLiveScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    // AUDIT FIX: observe app lifecycle so background time doesn't burn
    // battery/data with the 5s pending-jobs poll.
    WidgetsBinding.instance.addObserver(this);
    // Use addPostFrameCallback so ref is safe to use after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSocket();
      _initNotifications();
      _maybeStartWorkerPoll();
      // Location chain: restore last pick, else GPS auto-detect + nearest
      // serviceable city — so the home bar and city-scoped feeds are correct
      // without the user opening the picker.
      ensureLocationInitialized(ref);
      // CACHE WARM (client bug: Instant Help showed a ~4s blank grid on
      // first open): kick the trades-master fetch NOW, at app start. The
      // provider keepAlives for 10 min, so the grid is already populated
      // when the user reaches it — the skeleton only ever shows on a truly
      // cold cache with a slow connection.
      ref.read(proTradesProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingPollTimer?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  /// Pause the pending-jobs poll while backgrounded; resume on return.
  /// (The worker GPS stream is deliberately NOT paused — an en-route worker
  /// must keep sharing location even with the phone pocketed.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_pendingPollTimer?.isActive ?? false) {
        _pollWasRunning = true;
        _pendingPollTimer?.cancel();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pollWasRunning) {
        _pollWasRunning = false;
        _startPendingBookingPoll();
      }
      // Catch jobs that arrived while backgrounded (poll was paused, FCM
      // only showed a tray banner — popup never opened).
      unawaited(_pollPendingBookingsOnce());
      ref.invalidate(myBookingsProvider);
    }
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
    await notifService.initialize(
      onLocalNotificationTap: (payload) {
        unawaited(
          _handleNotificationData(payload, fromUserGesture: true),
        );
      },
    );

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
        ref.read(debugLogProvider.notifier).log('FCM token synced on start');
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

    // Join personal chat room so the server can push `new_message` events.
    final user = await ref.read(currentUserProvider.future);
    if (user != null) socketService.joinUserRoom(user.id);

    _notifSub?.cancel();
    _notifSub = socketService.notifications.listen((data) {
      final event = data['_event'] as String?;
      final id = data['id'] as String?;

      if (event == 'new_booking_request') {
        if (id != null &&
            !_shownBookingIds.contains(id) &&
            !_declinedBookingIds.contains(id)) {
          ref.read(debugLogProvider.notifier).log('[SOURCE: SOCKET] Incoming job $id');
          unawaited(_showIncomingJobScreen(data));
        }
      } else if (event == 'booking_accepted') {
        ref.invalidate(myBookingsProvider);
        if (mounted) _goToTab(0);
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
    _pendingPollTimer?.cancel();
    // Immediate first check — periodic alone waits a full 5s.
    unawaited(_pollPendingBookingsOnce());
    _pendingPollTimer = Timer.periodic(
      const Duration(seconds: AppConfig.pendingJobsPollIntervalSeconds),
      (_) {
        unawaited(_pollPendingBookingsOnce());
      },
    );
  }

  Future<void> _pollPendingBookingsOnce() async {
    try {
      final pending =
          await ref.read(bookingRepositoryProvider).getPendingBookings();
      for (final booking in pending) {
        final id = booking['id'] as String?;
        if (id != null &&
            !_shownBookingIds.contains(id) &&
            !_declinedBookingIds.contains(id)) {
          ref
              .read(debugLogProvider.notifier)
              .log('[SOURCE: HTTP_POLL] Incoming job $id');
          await _showIncomingJobScreen(
            Map<String, dynamic>.from(booking as Map),
          );
        }
      }
    } catch (_) {
      // Silent — FCM is the primary delivery channel
    }
  }

  // ── FCM Message Handlers ─────────────────────────────────────────────────

  void _handleFcmMessage(RemoteMessage message) {
    unawaited(_handleNotificationData(
      message.data.map((k, v) => MapEntry(k, '$v')),
      notificationTitle: message.notification?.title,
      fromUserGesture: false,
    ));
  }

  void _handleNotificationTap(RemoteMessage message) {
    unawaited(_handleNotificationData(
      message.data.map((k, v) => MapEntry(k, '$v')),
      notificationTitle: message.notification?.title,
      fromUserGesture: true,
    ));
  }

  Future<void> _handleNotificationData(
    Map<String, String> data, {
    String? notificationTitle,
    bool fromUserGesture = false,
  }) async {
    if (!mounted) return;
    final type = data['type'];
    final bookingId = data['bookingId'];

    if (type == 'new_booking') {
      // Dedup auto-delivery only. Taps always open the popup — workers often
      // see the tray banner while backgrounded and expect the accept screen.
      // Never reopen after this worker already declined/dismissed.
      if (bookingId != null && _declinedBookingIds.contains(bookingId)) {
        debugPrint('[FCM] Skipping declined booking $bookingId');
        return;
      }
      if (!fromUserGesture &&
          bookingId != null &&
          _shownBookingIds.contains(bookingId)) {
        debugPrint('[FCM] Skipping duplicate auto-popup for $bookingId');
        return;
      }

      ref
          .read(debugLogProvider.notifier)
          .log('[SOURCE: FCM] Incoming job $bookingId');

      await _showIncomingJobScreen({
        'id': bookingId,
        'skill': data['skill'] ?? 'General Help',
        'customer_name': notificationTitle ?? AppStrings.fcmDefaultTitle,
        'serviceLocation': data['serviceLocation'] ?? '',
        'amount': double.tryParse(data['amount'] ?? '0') ?? 0.0,
      });
      return;
    }

    if (type == 'booking_accepted') {
      ref.invalidate(myBookingsProvider);
      if (mounted) _goToTab(0);
    }
  }

  // ── Incoming Job Screen ──────────────────────────────────────────────────

  Future<void> _showIncomingJobScreen(Map<String, dynamic> bookingData) async {
    if (!mounted) return;
    final id = bookingData['id']?.toString();

    // Don't stack multiple incoming screens; keep the ID unmarked so a later
    // tap/poll can present it once the current one closes.
    if (_incomingJobOpen) return;

    // Mark only once we're about to present — avoids permanent skip if
    // !mounted aborts before Navigator.push.
    if (!mounted) return;
    _incomingJobOpen = true;
    if (id != null && id.isNotEmpty) _shownBookingIds.add(id);

    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => IncomingJobScreen(bookingData: bookingData),
          fullscreenDialog: true,
        ),
      );
      if (!mounted) return;
      if (result != null && result['accepted'] == true) {
        ref.invalidate(myBookingsProvider);
        _goToTab(0); // Home — active job card
      } else {
        final declined = result?['declinedIds'];
        if (declined is List) {
          for (final d in declined) {
            final did = d?.toString();
            if (did != null && did.isNotEmpty) _declinedBookingIds.add(did);
          }
        } else if (id != null) {
          // Decline / timeout / empty-queue close — keep out of poll/FCM reopen.
          _declinedBookingIds.add(id);
        }
        if (id != null) _shownBookingIds.remove(id);
      }
    } finally {
      _incomingJobOpen = false;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLive = ref.watch(workerLiveStateProvider);
    // If the user's worker status is discovered/healed mid-session (e.g. the
    // Go Live screen proved registration against the server and refreshed
    // currentUserProvider), start the pending-jobs poll now — it's the FCM
    // fallback and previously only started when isWorker was true at boot.
    ref.listen(currentUserProvider, (prev, next) {
      final becameWorker = next.asData?.value?.isWorker == true;
      if (becameWorker && !(_pendingPollTimer?.isActive ?? false)) {
        _startPendingBookingPoll();
      }
    });
    // Profile back / Home avatar write [mainTabIndexProvider]; keep the
    // bottom bar body in sync without Navigator.pop on the shell.
    ref.listen<int>(mainTabIndexProvider, (prev, next) {
      if (next != _currentIndex) {
        setState(() => _currentIndex = next);
      }
    });

    // Solid scaffold colour (not transparent) so the FAB notch never falls
    // through to the black window behind — that was the harsh "black scoop".
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: Stack(
          children: [
            _screens[_currentIndex],
            // Gixbee 2026: Uber-style persistent activity pill — the active
            // booking stays visible on every tab. Home (index 0) already
            // renders ActiveBookingCard inline, so skip it there.
            if (_currentIndex != 0)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 4,
                child: SafeArea(
                  top: false,
                  child: ActiveBookingCard(),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _GoLiveFab(isLive: isLive, onTap: _openGoLive),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 64,
        color: scheme.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(scheme, index: 0, icon: Icons.home_outlined,
                activeIcon: Icons.home, label: 'Home'),
            _navItem(scheme, index: 1, icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long, label: 'Bookings'),
            const SizedBox(width: 56), // gap for the center Go Live FAB
            _navItem(scheme, index: 2, icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble, label: 'Messages'),
            _navItem(scheme, index: 3, icon: Icons.person_outline,
                activeIcon: Icons.person, label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    ColorScheme scheme, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final selected = _currentIndex == index;
    // Shell accent: violet in Gixbee Dark, Grab green in light.
    final color = selected ? context.gx.accent : scheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
        onTap: () => _goToTab(index),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        ),
      ),
    );
  }
}

/// Center bottom-nav action that launches the worker Go-Live engine.
/// Turns green while the worker is live so the state is visible from any tab.
class _GoLiveFab extends StatelessWidget {
  final bool isLive;
  final VoidCallback onTap;
  const _GoLiveFab({required this.isLive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    // Live = functional green; idle FAB uses theme shell gradient.
    return SizedBox(
      width: 58,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isLive
              ? const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)])
              : LinearGradient(colors: gx.accentGradient),
          boxShadow: [
            BoxShadow(
              color: (isLive ? const Color(0xFF10B981) : gx.accent)
                  .withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isLive ? Icons.podcasts : Icons.bolt,
                    color: gx.onAccent, size: 22),
                Text('Go Live',
                    style: TextStyle(
                        color: gx.onAccent,
                        fontSize: 7,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
