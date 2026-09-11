import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/debug_log_service.dart';
import 'services/location_bootstrap.dart';
import 'services/location_service.dart';
import 'core/config/app_strings.dart';
import 'theme.dart';
import 'features/home/home_screen.dart';
import 'features/home/active_booking_card.dart';
import 'features/messages/messages_list_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/jobs/booking_detail_screen.dart';
import 'features/jobs/my_bookings_screen.dart';
import 'features/jobs/find_job_module.dart';
import 'features/business/hiring_requests_screen.dart';
import 'features/events/event_plan_detail_screen.dart';
import 'features/jobs/hiring_progress_screen.dart';
import 'features/rentals/my_rentals_screen.dart';
import 'features/rentals/owner_rentals_screen.dart';
import 'features/booking/incoming_job_screen.dart';
import 'features/booking/voice_call_screen.dart';
import 'features/billing/job_pack_screen.dart';
import 'services/voice_call_controller.dart';
import 'features/jobs/pro_skill_provider.dart';
import 'features/profile/addresses/address_picker_bottom_sheet.dart';
import 'features/worker/go_live_screen.dart';
import 'repositories/worker_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/booking_repository.dart';
import 'repositories/booking_status_provider.dart';
import 'services/auth_token_service.dart';
import 'services/notification_service.dart';
import 'services/socket_service.dart';
import 'shared/models/user.dart';
import 'shared/widgets/dribbble_background.dart';
import 'core/main_tab_provider.dart';

/// Push `data.type` values that mean "this booking changed" — every one of
/// them should refresh the booking lists and the live status stream.
/// `new_booking` is excluded: it opens the incoming-job screen instead.
const _bookingStateTypes = {
  'booking_accepted',
  'booking_cancelled',
  'booking_status_update',
  'booking_search_expanded',
  'worker_arrived',
  'job_complete',
  'cancel_requested',
  'cancel_declined',
  'worker_no_progress',
  'late_cancel_compensation_paid',
  'dispute_resolved',
};

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});

  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription? _notifSub; // AUDIT FIX: was leaked (never cancelled)
  StreamSubscription? _voiceSub;

  /// One-shot guard for the first-run location prompt (Swiggy pattern).
  bool _locationPromptShown = false;

  /// Non-null while GPS is blocked ('service_off' | 'denied_forever' |
  /// Tracks booking IDs already shown — prevents duplicate popups from
  /// FCM, socket, and HTTP reconciliation firing for the same booking.
  final Set<String> _shownBookingIds = {};

  /// Worker declined / dismissed these — never re-open via HTTP/FCM/socket
  /// for the rest of this session (backend also drops Redis pending).
  final Set<String> _declinedBookingIds = {};

  /// True while IncomingJobScreen is on the navigator stack — blocks stacked
  /// duplicate pushes from socket + FCM racing.
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
    if (_sessionExitStarted) return;
    // Block tab switches once the session is gone (Profile may still be
    // painting "Session Expired" for a frame before Welcome replaces us).
    unawaited(() async {
      final userAsync = ref.read(currentUserProvider);
      if (userAsync is AsyncData<User?> && userAsync.value == null) {
        _forceSessionEnd();
        return;
      }
      final authed = await ref.read(authTokenServiceProvider).hasToken();
      if (!authed) {
        _forceSessionEnd();
        return;
      }
      if (!mounted) return;
      ref.read(mainTabIndexProvider.notifier).state = index;
      if (_currentIndex != index) setState(() => _currentIndex = index);
    }());
  }

  void _openGoLive() {
    if (_sessionExitStarted) return;
    final userAsync = ref.read(currentUserProvider);
    if (userAsync is AsyncData<User?> && userAsync.value == null) {
      _forceSessionEnd();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoLiveScreen()),
    );
  }

  bool _sessionExitStarted = false;

  /// Leave the shell entirely (no bottom nav / Go Live). Clears tokens even
  /// if a stale access token is still on disk — profile null means logged out.
  void _forceSessionEnd() {
    if (_sessionExitStarted) return;
    _sessionExitStarted = true;
    unawaited(forceLogoutToWelcomeFromWidget(ref));
  }

  /// Soft check used on resume/tab — only exit when there is truly no token.
  void _kickToWelcomeIfLoggedOut() {
    unawaited(() async {
      final authed = await ref.read(authTokenServiceProvider).hasToken();
      if (authed || !mounted) return;
      _forceSessionEnd();
    }());
  }

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle to reconcile offers received while backgrounded.
    WidgetsBinding.instance.addObserver(this);
    // Use addPostFrameCallback so ref is safe to use after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSocket();
      _initNotifications();
      _checkWorkerPendingOnce();
      // Location chain: restore last pick, else GPS auto-detect + nearest
      // serviceable city — so the home bar and city-scoped feeds are correct
      // without the user opening the picker.
      // If NEITHER resolves (fresh install with device location off or the
      // permission denied), prompt IMMEDIATELY with the address picker —
      // Swiggy-style — instead of leaving a blank "Select Location" the
      // user has to discover on their own. The sheet offers all three exits:
      // use live location, pick a saved address, or pin on the map.
      ensureLocationInitialized(ref).then((_) {
        if (!mounted) return;
        if (ref.read(selectedLocationProvider) == null) {
          _promptLocationPicker();
        }
        // Swiggy pattern part 2: ASK for device location on app open when
        // it's merely un-granted.
        unawaited(_checkGpsAccess());
      });
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
    _notifSub?.cancel();
    _voiceSub?.cancel();
    super.dispose();
  }

  /// Socket + FCM are primary. On resume, perform one HTTP reconciliation for
  /// offers delivered while the app was suspended.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _kickToWelcomeIfLoggedOut();
      unawaited(_reconcilePendingBookings());
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
      if (_sessionExitStarted || !mounted) return;
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
      if (_sessionExitStarted || !mounted) return;
      try {
        final token = await notifService.getDeviceToken();
        if (token == null) return;
        if (_sessionExitStarted || !mounted) return;
        await ref.read(authRepositoryProvider).registerFcmToken(token);
        if (_sessionExitStarted || !mounted) return;
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
      } else if (_bookingStateTypes.contains(event)) {
        // The live status stream consumes these directly; the lists and the
        // home active-job card need an explicit refresh.
        ref.invalidate(myBookingsProvider);
        ref.invalidate(activeBookingProvider);
        if (event == 'booking_accepted' && mounted) _goToTab(0);
      }
    });

    _voiceSub?.cancel();
    _voiceSub = socketService.voiceCalls.listen((data) {
      final event = data['_event'] as String?;
      if (event == 'voice_call_invite' && mounted) {
        unawaited(_presentIncomingVoiceCall(data));
      }
    });
  }

  Future<void> _presentIncomingVoiceCall(Map<String, dynamic> invite) async {
    if (!mounted) return;
    final ctrl = ref.read(voiceCallControllerProvider);
    if (ctrl.phase != VoiceCallPhase.idle &&
        ctrl.phase != VoiceCallPhase.ended) {
      return;
    }
    await VoiceCallScreen.showIncoming(context, invite: invite);
  }

  // ── One-shot worker queue reconciliation (FCM + Socket fallback) ────────

  Future<void> _checkWorkerPendingOnce() async {
    // await .future to get the resolved value — .value is null at initState time
    final user = await ref.read(currentUserProvider.future);
    if (user?.isWorker == true) {
      await _reconcilePendingBookings();
    }
  }

  Future<void> _reconcilePendingBookings() async {
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
              .log('[SOURCE: HTTP_RECONCILE] Incoming job $id');
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
        'customer_name': () {
          final name = data['customer_name']?.toString().trim() ?? '';
          if (name.isNotEmpty) return name;
          return notificationTitle ?? AppStrings.fcmDefaultTitle;
        }(),
        'serviceLocation': data['serviceLocation'] ?? '',
        // Coords → the "· 2.3 km away" line on the incoming card. Empty
        // strings parse to null and the card just omits the distance.
        'serviceLat': data['serviceLat'] ?? '',
        'serviceLng': data['serviceLng'] ?? '',
        // Server timestamp → wall-clock accept deadline (createdAt + 90s).
        // Without it the card restarted a full window on FCM open.
        'createdAt': data['createdAt'] ?? '',
        'notifiedAt': data['notifiedAt'] ?? '',
        'amount': double.tryParse(data['amount'] ?? '0') ?? 0.0,
        'description': data['description'] ?? '',
        'preferredLanguages': _parseFcmLanguages(data['preferredLanguages']),
      });
      return;
    }

    if (type == 'voice_call' && bookingId != null) {
      await _presentIncomingVoiceCall({
        'bookingId': bookingId,
        'callId': data['callId'],
        'callerId': data['callerId'],
        'callerName': data['callerName'] ?? notificationTitle ?? 'Incoming call',
      });
      return;
    }

    // Smart Hiring deep links
    if (type == 'rental_request' || type == 'rental_status') {
      if (fromUserGesture && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) =>
          data['audience'] == 'owner' || type == 'rental_request' ? const OwnerRentalsScreen() : const MyRentalsScreen()));
      }
      return;
    }
    if (type == 'hiring_progress') {
      final interestId = data['interestId'];
      if (fromUserGesture && mounted && interestId != null && interestId.isNotEmpty) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => HiringProgressScreen(interestId: interestId)));
      }
      return;
    }
    if (type == 'event_enquiry' || type == 'event_quote' || type == 'event_update') {
      final planId = data['planId'];
      if (fromUserGesture && mounted && planId != null && planId.isNotEmpty) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => EventPlanDetailScreen(planId: planId)));
      }
      return;
    }
    if (type == 'hiring_offer' || type == 'hiring_status') {
      if (fromUserGesture && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const FindJobModule(initialIndex: 1),
          ),
        );
      }
      return;
    }
    if (type == 'hiring_delivered' || type == 'hiring_guarantee_failed') {
      if (fromUserGesture && mounted) {
        final requestId = data['requestId'];
        if (requestId != null && requestId.isNotEmpty) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  HiringRequestDetailScreen(requestId: requestId),
            ),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HiringRequestsScreen()),
          );
        }
      }
      return;
    }

    if (_bookingStateTypes.contains(type)) {
      // Everything that moves a booking forward: refresh the lists and make
      // the live status stream re-poll now. Previously only `booking_accepted`
      // was handled, so a push that arrived while the socket was down (or
      // while backgrounded) left the open screen waiting for its next poll.
      ref.invalidate(myBookingsProvider);
      ref.invalidate(activeBookingProvider);
      if (bookingId != null) {
        ref.read(bookingStatusNudgeProvider).poke(bookingId);
      }
      if (type == 'booking_accepted' && mounted) _goToTab(0);
      // A cancel request needs an answer, so the tap must land on the job
      // itself — the tray banner is the pro's only prompt.
      if (type == 'cancel_requested' &&
          fromUserGesture &&
          bookingId != null &&
          mounted) {
        await _openBookingDetail(bookingId);
      }
    }
  }

  Future<void> _openBookingDetail(String bookingId) async {
    try {
      final booking =
          await ref.read(bookingRepositoryProvider).getBookingById(bookingId);
      if (!mounted || booking == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: booking)),
      );
    } catch (e) {
      debugPrint('[FCM] Could not open booking $bookingId: $e');
    }
  }

  /// FCM data values are strings — languages arrive as JSON array text.
  List<String> _parseFcmLanguages(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── Incoming Job Screen ──────────────────────────────────────────────────

  Future<void> _showIncomingJobScreen(Map<String, dynamic> bookingData) async {
    if (!mounted) return;
    final id = bookingData['id']?.toString();

    // Don't stack multiple incoming screens; keep the ID unmarked so a later
    // tap/reconciliation can present it once the current one closes.
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
          // Decline/timeout/empty queue — keep out of HTTP/FCM reopen.
          _declinedBookingIds.add(id);
        }
        if (id != null) _shownBookingIds.remove(id);
        // Worker ran out of credits during accept — open the pack screen
        // now that we have a live context (IncomingJobScreen is fully gone).
        if (result?['openJobPack'] == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const JobPackScreen()),
          );
        }
      }
    } finally {
      _incomingJobOpen = false;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  /// Swiggy-style first-run prompt: opens the address picker sheet when the
  /// app has no location at all. One-shot per session — if the user swipes
  /// it away they can still pick later from the home location bar.
  void _promptLocationPicker() {
    if (_locationPromptShown || !mounted) return;
    _locationPromptShown = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddressPickerBottomSheet(),
    );
  }

  // ── GPS access banner (Swiggy "Location Permission is Off") ──────────

  /// Evaluate GPS availability. When [promptIfAskable] and the permission is
  /// merely 'denied' (re-promptable), trigger the OS dialog once by
  /// requesting a position — that IS the ask-on-open.
  Future<void> _checkGpsAccess() async {
    try {
      final svc = ref.read(locationServiceProvider);
      final reason = await svc.gpsBlockReason();
      if (reason == 'denied') {
        await svc.getCurrentPosition(); // surfaces the OS permission dialog
      }
    } catch (_) {}
  }



  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLive = ref.watch(workerLiveStateProvider);
    // If worker status is discovered mid-session, reconcile the queue once.
    // Future offers arrive through Socket.IO / FCM.
    ref.listen(currentUserProvider, (prev, next) {
      final wasWorker = prev?.asData?.value?.isWorker == true;
      final becameWorker = !wasWorker && next.asData?.value?.isWorker == true;
      if (becameWorker) {
        unawaited(_reconcilePendingBookings());
      }
      // Profile resolved to null ⇒ session dead — tear down shell + nav.
      if (next is AsyncData<User?> && next.value == null) {
        _forceSessionEnd();
      }
    });
    ref.listen(authStateProvider, (prev, next) {
      next.whenData((authed) {
        if (!authed) _forceSessionEnd();
      });
    });
    // Profile back / Home avatar write [mainTabIndexProvider]; keep the
    // bottom bar body in sync without Navigator.pop on the shell.
    ref.listen<int>(mainTabIndexProvider, (prev, next) {
      if (next != _currentIndex) {
        setState(() => _currentIndex = next);
      }
    });

    final userAsync = ref.watch(currentUserProvider);
    // Never paint bottom nav / Go Live while logged out — even for one frame
    // before Welcome replaces this route.
    final sessionGone = _sessionExitStarted ||
        (userAsync is AsyncData<User?> && userAsync.value == null);
    if (sessionGone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _forceSessionEnd();
      });
      return Scaffold(
        backgroundColor: context.gx.bg,
        body: Center(
          child: CircularProgressIndicator(color: context.gx.accent),
        ),
      );
    }

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
                  colors: [
                    GixbeeTheme.accentGreen,
                    GixbeeTheme.accentGreenDark,
                  ])
              : LinearGradient(colors: gx.accentGradient),
          boxShadow: [
            BoxShadow(
              color: (isLive ? GixbeeTheme.accentGreen : gx.accent)
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
