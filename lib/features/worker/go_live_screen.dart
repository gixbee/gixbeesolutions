import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/payments_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../services/location_service.dart';
import '../../services/socket_service.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../jobs/register_pro_screen.dart';
import '../booking/incoming_job_screen.dart';
import '../billing/job_pack_screen.dart';
import 'worker_languages_card.dart';
import 'service_radius_card.dart';
import 'go_live_job_feed.dart';
import 'go_live_screen_widgets.dart';
import 'worker_instant_eligibility.dart';
import 'worker_live_presence.dart';
import 'worker_live_toggle.dart';

export 'worker_instant_eligibility.dart' show goLiveDashboardProvider;

/// Worker "Go Live" engine.
///
/// Mirrors the mockup's center-FAB flow:
///   setup (services + Go-Live button) → live mode (timer + job feed).
///
/// Online state is owned by the server (`POST /workers/live-toggle`); this
/// screen reflects it via [workerLiveStateProvider] and surfaces incoming jobs
/// from the shared [socketServiceProvider] stream.
class GoLiveScreen extends ConsumerStatefulWidget {
  const GoLiveScreen({super.key});

  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  final _languagesSectionKey = GlobalKey();

  /// One-shot heal of the cached user when the server proves worker status
  /// (see the registration gate in build) — guards an invalidate loop.
  bool _healedUserFlag = false;

  /// Optimistic local copy of the active-service set (null = derive from
  /// server data). Empty `activeSkills` from the server means "all active".
  Set<String>? _activeOverride;
  bool _savingSkills = false;
  DateTime? _liveSince;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  /// Incoming job requests received while live (newest first).
  final List<Map<String, dynamic>> _jobFeed = [];
  StreamSubscription<Map<String, dynamic>>? _socketSub;

  /// True when the live-mode heartbeat can't get a GPS fix any more — the
  /// pro is drifting out of dispatch and must be told, not left "waiting".
  bool _gpsLost = false;

  /// In-flight guard for the periodic-plan payment button.
  bool _payingFee = false;

  /// Razorpay checkout for the DIRECT period-fee payment (no wallet hop).
  /// Lazily created on first use; cleared in dispose.
  Razorpay? _razorpay;

  @override
  void initState() {
    super.initState();
    _socketSub =
        ref.read(socketServiceProvider).notifications.listen(_onSocketEvent);
    // If already live when opening this screen, start GPS presence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(workerLiveStateProvider)) {
        unawaited(_startTicker(reset: false));
        unawaited(ref.read(workerLivePresenceProvider).start());
        unawaited(_refreshPendingFeed());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _socketSub?.cancel();
    _razorpay?.clear();
    super.dispose();
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final event = data['_event'] as String?;
    final id = (data['id'] ?? data['bookingId'])?.toString();
    if (event == 'new_booking_request' && id != null) {
      if (_jobFeed.any((j) => j['id']?.toString() == id)) return;
      setState(() => _jobFeed.insert(0, data));
      unawaited(_refreshPendingFeed());
    } else if (event == 'booking_status_update' ||
        event == 'booking_accepted' ||
        event == 'booking_cancelled' ||
        event == 'booking_completed') {
      if (id != null) {
        setState(() => _jobFeed.removeWhere((j) => j['id']?.toString() == id));
      } else {
        final status = data['status']?.toString().toUpperCase();
        if (status != null && status != 'REQUESTED') {
          final targetId = (data['bookingId'] ?? data['id'])?.toString();
          if (targetId != null) {
            setState(() =>
                _jobFeed.removeWhere((j) => j['id']?.toString() == targetId));
          }
        }
      }
      unawaited(_refreshPendingFeed());
    }
  }

  Future<void> _refreshPendingFeed() async {
    if (!mounted || !ref.read(workerLiveStateProvider)) return;
    try {
      final pending =
          await ref.read(bookingRepositoryProvider).getPendingBookings();
      if (!mounted) return;
      final pendingMaps = pending
          .whereType<Map>()
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
      final pendingIds = pendingMaps.map((b) => b['id']?.toString()).toSet();
      setState(() {
        _jobFeed.removeWhere((j) => !pendingIds.contains(j['id']?.toString()));
        for (final item in pendingMaps) {
          final id = item['id']?.toString();
          if (id != null && !_jobFeed.any((j) => j['id']?.toString() == id)) {
            _jobFeed.add(item);
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _startTicker({bool reset = false}) async {
    const storage = FlutterSecureStorage();
    if (reset || _liveSince == null) {
      if (!reset) {
        final stored = await storage.read(key: 'worker_live_since');
        if (stored != null) {
          _liveSince = DateTime.tryParse(stored);
        }
      }
      if (_liveSince == null || reset) {
        _liveSince = DateTime.now();
        await storage.write(
            key: 'worker_live_since', value: _liveSince!.toIso8601String());
      }
    }
    // Eagerly compute elapsed so the UI never flashes 0:00:00 on re-entry.
    if (mounted && _liveSince != null) {
      setState(() => _elapsed = DateTime.now().difference(_liveSince!));
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _liveSince == null) return;
      setState(() => _elapsed = DateTime.now().difference(_liveSince!));
    });
  }

  Future<void> _stopTicker() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'worker_live_since');
    _ticker?.cancel();
    _ticker = null;
    _liveSince = null;
    if (mounted) setState(() => _elapsed = Duration.zero);
  }

  Future<void> _toggle() async {
    if (ref.read(workerLiveToggleBusyProvider)) return;
    final wasLive = ref.read(workerLiveStateProvider);
    await runWorkerLiveToggle(
      context,
      ref,
      scrollToLanguagesKey: _languagesSectionKey,
      dashboard: ref.read(goLiveDashboardProvider).asData?.value,
    );
    if (!mounted) return;
    final nowLive = ref.read(workerLiveStateProvider);
    if (nowLive && !wasLive) {
      unawaited(_startTicker(reset: true));
      unawaited(_refreshPendingFeed());
    } else if (!nowLive && wasLive) {
      unawaited(_stopTicker());
      _jobFeed.clear();
      if (_gpsLost) setState(() => _gpsLost = false);
    }
  }

  void _toast(String msg, {required bool error}) {
    showGxSnack(
      context,
      msg,
      type: error ? GxSnackType.error : GxSnackType.success,
    );
  }

  List<String> _spokenLanguages(dynamic raw) => parseSpokenLanguages(raw);

  /// Pay the period fee — DIRECT Razorpay checkout (production path): the
  /// server creates the order at the Master-Entries price, the user pays in
  /// checkout, and the WEBHOOK unlocks the jobs. Falls back to the wallet
  /// charge only when the gateway isn't configured (dev machines).
  // ignore: unused_element
  Future<void> _payPeriodFee() async {
    if (_payingFee) return;
    setState(() => _payingFee = true);
    try {
      final order =
          await ref.read(workerRepositoryProvider).createPeriodFeeOrder();
      final user = ref.read(currentUserProvider).value;

      _razorpay ??= Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onFeePaymentSuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onFeePaymentError)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

      _razorpay!.open({
        'key': order['keyId'] ?? AppConfig.razorpayKey,
        'amount': order['amount'], // paise, server-priced
        'order_id': order['orderId'],
        'currency': order['currency'] ?? 'INR',
        'name': AppConfig.appName,
        'description': 'Gixbee platform fee — unlock your next jobs',
        'timeout': AppConfig.paymentTimeoutSeconds,
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
      });
      // _payingFee is released by the success/error handlers.
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? '')
          : '';
      if (msg.contains('not configured')) {
        // Dev fallback: gateway absent → wallet charge keeps testing possible.
        await _payPeriodFeeViaWallet();
      } else {
        if (mounted) {
          _toast(msg.isEmpty ? 'Could not start the payment' : msg,
              error: true);
        }
      }
      if (mounted) setState(() => _payingFee = false);
    } catch (_) {
      if (mounted) {
        _toast('Could not start the payment', error: true);
        setState(() => _payingFee = false);
      }
    }
  }

  Future<void> _onFeePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final confirmed = await ref.read(paymentsRepositoryProvider)
        .confirmCapturedPayment(response.orderId, response.paymentId);
    if (!mounted) return;
    setState(() => _payingFee = false);
    _toast(confirmed ? 'Payment received. Your jobs are unlocked.' :
        'Payment is being confirmed.', error: false);
    ref.invalidate(goLiveDashboardProvider);
    if (confirmed) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) ref.invalidate(goLiveDashboardProvider);
    });
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) ref.invalidate(goLiveDashboardProvider);
    });
  }

  void _onFeePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _payingFee = false);
    _toast('Payment failed: ${response.message ?? 'try again'}', error: true);
  }

  /// Dev-only fallback when Razorpay keys aren't configured on the server.
  Future<void> _payPeriodFeeViaWallet() async {
    try {
      final res = await ref.read(workerRepositoryProvider).payPeriodFee();
      ref.invalidate(goLiveDashboardProvider);
      if (mounted) {
        _toast((res['message'] ?? 'Payment received.').toString(),
            error: false);
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? 'Payment failed')
          : 'Payment failed';
      if (mounted) _toast(msg, error: true);
    } catch (_) {
      if (mounted) _toast('Payment failed', error: true);
    }
  }

  /// Job Credits card showing current balance and buy pack button
  Widget _jobCreditsCard(Map<String, dynamic>? dash) {
    final balance = (dash?['jobCredits'] as num?)?.toInt() ?? 0;
    return GoLiveJobCreditsCard(
      balance: balance,
      onBuyPack: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JobPackScreen()),
      ),
    );
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingJobScreen(bookingData: job),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    setState(() => _jobFeed.removeWhere((j) => j['id'] == job['id']));
    unawaited(_refreshPendingFeed());
    // Worker ran out of credits during accept — navigate to the pack screen
    // now that we have a valid context (IncomingJobScreen is fully gone).
    if (result?['openJobPack'] == true) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JobPackScreen()),
      );
    }
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  /// Sync the local live flag with the server's `isActive` from the
  /// dashboard. Fixes the "Go Live Now" showing after app restart while the
  /// backend still has this worker live.
  void _syncLiveFromServer(Map<String, dynamic>? dash) {
    if (dash == null || !dash.containsKey('isActive')) return;
    final serverLive = dash['isActive'] == true;
    final localLive = ref.read(workerLiveStateProvider);
    if (serverLive == localLive) return;
    ref.read(workerLiveStateProvider.notifier).state = serverLive;
    final presence = ref.read(workerLivePresenceProvider);
    if (serverLive) {
      if (_liveSince == null) unawaited(_startTicker(reset: false));
      unawaited(presence.start());
      unawaited(_refreshPendingFeed());
    } else {
      unawaited(_stopTicker());
      _jobFeed.clear();
      presence.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(goLiveDashboardProvider, (prev, next) {
      final dash = next.asData?.value;
      if (dash != null) _syncLiveFromServer(dash);
    });
    ref.listen(myBookingsProvider, (prev, next) {
      if (ref.read(workerLiveStateProvider)) {
        unawaited(_refreshPendingFeed());
      }
    });
    final scheme = Theme.of(context).colorScheme;
    final isLive = ref.watch(workerLiveStateProvider);
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Go Live',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: context.gx.ink)),
        centerTitle: true,
        actions: [
          if (isLive)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _fmt(_elapsed),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GixbeeTheme.accentGreen,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => GxNetworkError(
          error: e,
          title: 'Could not load your profile',
          onRetry: () => ref.invalidate(currentUserProvider),
        ),
        data: (user) {
          if (user == null) {
            return GoLiveNotAWorker(scheme: scheme);
          }

          final dashAsync = ref.watch(goLiveDashboardProvider);
          final dashData = dashAsync.asData?.value;

          // REGISTRATION GATE — server truth over the cached flag.
          // `user.isWorker` comes from users.hasWorkerProfile, which stayed
          // false for pros who registered via the talent/Earn Hourly path
          // (client bug: fully VERIFIED pro shown "Register as Pro"). The
          // dashboard endpoint resolves the real profile (and lazily creates
          // it from the talent profile).
          //
          // Important: The backend auto-creates an empty PENDING shell and
          // forces hasWorkerProfile=true just because this endpoint is hit.
          // So we must ALWAYS do a "ghost profile" check, regardless of the
          // cached flag.
          //
          // While the dashboard is still in flight, a user whose cached flag
          // says "not a pro" gets the wizard CTA straight away rather than a
          // spinner — the dashboard result still overrides it a moment later
          // if the server disagrees (talent-path pros).
          if (dashData == null) {
            if (!user.isWorker) {
              return GoLiveNotAWorker(scheme: scheme);
            }
            if (dashAsync.hasError) {
              return GxNetworkError(
                error: dashAsync.error,
                title: 'Could not load dashboard',
                onRetry: () => ref.invalidate(goLiveDashboardProvider),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          final hasSkills =
              ((dashData['skills'] as List?)?.isNotEmpty ?? false);
          final verStatus =
              (dashData['verificationStatus'] as String?) ?? 'PENDING';

          // Ghost profile check: if no skills were ever submitted AND the status
          // is still PENDING, this is an auto-created shell from opening Earn Hourly.
          // Send them back to the wizard.
          if (!hasSkills && verStatus == 'PENDING') {
            return GoLiveNotAWorker(scheme: scheme);
          }

          // Server says registered with real skills — refresh the stale
          // cached user once if the old flag was false.
          if (!user.isWorker && !_healedUserFlag) {
            _healedUserFlag = true;
            Future.microtask(() => ref.invalidate(currentUserProvider));
          }

          final dash = dashData;
          return Stack(
            children: [
              RefreshIndicator(
                color: context.gx.accent,
                onRefresh: () async {
                  ref.invalidate(goLiveDashboardProvider);
                  unawaited(_refreshPendingFeed());
                  await ref.read(goLiveDashboardProvider.future);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: isLive
                      ? _buildLiveView(scheme, user, dash)
                      : _buildSetupView(
                          scheme, user, dash, dashAsync.isLoading),
                ),
              ),
              // Sticky Go Live / Offline Button
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildStickyFooter(isLive, dash),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSetupView(ColorScheme scheme, dynamic user,
      Map<String, dynamic>? dash, bool isLoading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          16, 16, 16, 100), // padding for sticky footer
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // WORKER PROFILE CARD
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.gx.bg, context.gx.card],
              ),
              border: Border.all(
                  color: context.gx.accent.withValues(alpha: 0.2), width: 1.5),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: context.gx.accentGradient,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'W',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: context.gx.onAccent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: context.gx.ink)),
                      const SizedBox(height: 3),
                      _buildVerificationBadge(dash),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 12, color: context.gx.accent),
                          const SizedBox(width: 5),
                          Text('Auto-updating GPS',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      context.gx.ink.withValues(alpha: 0.55))),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (() {
                        final r =
                            double.tryParse('${dash?['rating'] ?? 0}') ?? 0.0;
                        return r > 0 ? r.toStringAsFixed(1) : 'New';
                      })(),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: GixbeeTheme.accentGold),
                    ),
                    Text('★ rating',
                        style: TextStyle(
                            fontSize: 10, color: GixbeeTheme.accentGold)),
                    const SizedBox(height: 2),
                    Text('${dash?['earnings']?['jobsCompleted'] ?? 0} jobs',
                        style: TextStyle(
                            fontSize: 10,
                            color: context.gx.ink.withValues(alpha: 0.55))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _jobCreditsCard(dash),
          const SizedBox(height: 24),

          // SELECT SERVICES
          Row(
            children: [
              Expanded(
                child: Text('SERVICES TO OFFER TODAY',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.55),
                        letterSpacing: 1.2)),
              ),
              GxPressable(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterProScreen(
                              initialStep: 1,
                              isEditingSkills: true,
                            )),
                  );
                  if (!mounted) return;
                  ref.invalidate(goLiveDashboardProvider);
                  setState(() => _activeOverride = null);
                },
                child: Text(
                  'Add / edit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.gx.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (dash != null) ...[
            _serviceActivationCard(scheme, dash),
            if ((dash['skills'] as List? ?? const []).isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GxButton(
                  label: 'Add skills to go live',
                  icon: Icons.add_rounded,
                  filled: false,
                  accent: context.gx.accent,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterProScreen(
                                initialStep: 1,
                                isEditingSkills: true,
                              )),
                    );
                    if (!mounted) return;
                    ref.invalidate(goLiveDashboardProvider);
                  },
                ),
              ),
          ] else if (isLoading) ...[
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator())),
          ],

          const SizedBox(height: 14),
          // v126 language matching: going live requires at least one language;
          // customers with a language preference only notify overlapping pros.
          Text('LANGUAGES I SPEAK',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.gx.ink.withValues(alpha: 0.55),
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _languagesSectionKey,
            child: const WorkerLanguagesCard(),
          ),

          const SizedBox(height: 14),
          // How far this pro will travel — jobs outside it are never broadcast
          // to them (WorkersService.getNearby enforces it).
          const ServiceRadiusCard(),

          const SizedBox(height: 14),
          Text('YOUR LOCATION',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.gx.ink.withValues(alpha: 0.55),
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: context.gx.card2,
              border: Border.all(color: context.gx.border, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.gx.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.location_on,
                      size: 18, color: context.gx.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Location',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.gx.ink)),
                      const SizedBox(height: 2),
                      Text('GPS: Auto-updating · Accurate',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.gx.ink.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: GixbeeTheme.accentGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveView(
      ColorScheme scheme, dynamic user, Map<String, dynamic>? dash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mid-session GPS loss — the pro is decaying out of dispatch; say so
        // loudly with a one-tap fix instead of a silent "waiting" forever.
        if (_gpsLost)
          GxPressable(
            onTap: () =>
                ref.read(locationServiceProvider).openLocationSettings(),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: GixbeeTheme.accentGold.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.gps_off_rounded,
                      size: 20, color: GixbeeTheme.accentGold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'GPS signal lost — you may stop receiving jobs. Tap to '
                      'check location settings.',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // LIVE HERO
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [context.gx.bg, context.gx.card],
            ),
            border: Border(
              bottom: BorderSide(
                color: GixbeeTheme.accentGreen.withValues(alpha: 0.13),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse ring
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GixbeeTheme.accentGreen.withValues(alpha: 0.10),
                    ),
                  ),
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GixbeeTheme.accentGreen.withValues(alpha: 0.20),
                    ),
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GixbeeTheme.accentGreen,
                      boxShadow: [
                        BoxShadow(
                          color:
                              GixbeeTheme.accentGreen.withValues(alpha: 0.40),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child:
                        Icon(Icons.radar, color: context.gx.onAccent, size: 36),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Looking for nearby jobs...',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: context.gx.ink)),
              const SizedBox(height: 4),
              Text('Keep app open. You will be notified instantly.',
                  style: TextStyle(
                      fontSize: 13,
                      color: context.gx.ink.withValues(alpha: 0.55))),
            ],
          ),
        ),

        if (dash != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildLiveStatCard('Jobs Today',
                      '${dash['earnings']?['jobsCompleted'] ?? 0}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLiveStatCard(
                      'Earned', '₹${dash['earnings']?['today'] ?? 0}'),
                ),
              ],
            ),
          ),

        if (dash != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _jobCreditsCard(dash),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _jobFeedSection(scheme),
        ),

        const SizedBox(height: 100), // Sticky footer padding
      ],
    );
  }

  Widget _buildLiveStatCard(String label, String value) {
    return GoLiveStatCard(label: label, value: value);
  }

  /// Renders the Aadhaar/verification status row badge inside the profile card.
  /// PENDING → amber warning, REJECTED → red, VERIFIED → green tick.
  Widget _buildVerificationBadge(Map<String, dynamic>? dash) {
    final status = (dash?['verificationStatus'] as String?) ?? 'PENDING';
    return GoLiveVerificationBadge(status: status);
  }

  Widget _buildStickyFooter(bool isLive, Map<String, dynamic> dash) {
    final toggleBusy = ref.watch(workerLiveToggleBusyProvider);
    final credits = (dash['jobCredits'] as num?)?.toInt() ?? 0;
    final verStatus = (dash['verificationStatus'] as String?) ?? 'PENDING';
    final isVerified = verStatus == 'VERIFIED';
    final fromCard = ref.watch(workerSpokenLanguagesProvider);
    final missingLanguages = fromCard != null
        ? fromCard.isEmpty
        : dash['languages'] is List &&
            _spokenLanguages(dash['languages']).isEmpty;
    final isDisabled =
        !isLive && (credits <= 0 || !isVerified || missingLanguages);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gx.bg,
        border: Border(top: BorderSide(color: context.gx.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLive ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isLive
                  ? GixbeeTheme.accentGreen
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (!isLive && !isVerified) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: GixbeeTheme.accentGold.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top,
                      size: 14, color: GixbeeTheme.accentGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verStatus == 'REJECTED'
                          ? 'Verification rejected. Please re-upload your documents.'
                          : 'Your profile is under review. You can go live once verified.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: GixbeeTheme.accentGold,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isLive && missingLanguages) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: GixbeeTheme.accentGold.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.translate, size: 14, color: GixbeeTheme.accentGold),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select at least one language you speak before going live.',
                      style: TextStyle(
                          fontSize: 12,
                          color: GixbeeTheme.accentGold,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          GestureDetector(
            onTap: (toggleBusy || isDisabled) ? null : _toggle,
            child: Builder(
              builder: (context) {
                final offline = Theme.of(context).colorScheme.error;
                final online = GixbeeTheme.accentGreen;
                final onlineDark = GixbeeTheme.accentGreenDark;
                final gradient = isLive
                    ? [offline, GixbeeTheme.brandRed]
                    : [onlineDark, online];
                final glow = (isLive ? offline : online).withValues(alpha: 0.4);
                return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: glow,
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              foregroundDecoration: isDisabled
                  ? BoxDecoration(
                      color: context.gx.bg.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    )
                  : null,
              child: toggleBusy
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: context.gx.onAccent, strokeWidth: 3))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isLive ? Icons.power_settings_new : Icons.bolt,
                            color: context.gx.onAccent, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          isLive ? 'Go Offline' : 'Go Online',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: context.gx.onAccent),
                        ),
                      ],
                    ),
            );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Service activation ─────────────────────────────────────────────────

  Set<String> _effectiveActive(Map<String, dynamic> dash) {
    if (_activeOverride != null) return _activeOverride!;
    final skills = List<String>.from(dash['skills'] as List? ?? const []);
    final active = List<String>.from(dash['activeSkills'] as List? ?? const []);
    return (active.isEmpty ? skills : active).toSet();
  }

  Future<void> _toggleSkill(String skill, Map<String, dynamic> dash) async {
    if (_savingSkills) return;
    final previous = _effectiveActive(dash);
    final next = Set<String>.from(previous);
    if (next.contains(skill)) {
      if (next.length == 1) {
        _toast('At least one service must stay active', error: true);
        return;
      }
      next.remove(skill);
    } else {
      next.add(skill);
    }
    setState(() {
      _activeOverride = next;
      _savingSkills = true;
    });
    try {
      await ref.read(workerRepositoryProvider).setActiveSkills(next.toList());
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ??
              'Could not update services')
          : 'Could not update services';
      if (mounted) {
        setState(() => _activeOverride = previous);
        _toast(msg, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _activeOverride = previous);
        _toast('Could not update services', error: true);
      }
    } finally {
      if (mounted) setState(() => _savingSkills = false);
    }
  }

  Widget _serviceActivationCard(ColorScheme scheme, Map<String, dynamic> dash) {
    final skills = List<String>.from(dash['skills'] as List? ?? const []);
    if (skills.isEmpty) return const SizedBox.shrink();
    final active = _effectiveActive(dash);

    return Column(
      children: skills.map((skill) {
        final on = active.contains(skill);
        return GestureDetector(
          onTap: () => _toggleSkill(skill, dash),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? context.gx.card2 : context.gx.card,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: on ? context.gx.accent : context.gx.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: on
                        ? context.gx.accent.withValues(alpha: 0.2)
                        : context.gx.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(on ? Icons.bolt : Icons.design_services,
                      size: 18,
                      color: on
                          ? context.gx.accent
                          : context.gx.ink.withValues(alpha: 0.55)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(skill,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: on
                                  ? context.gx.ink
                                  : context.gx.ink.withValues(alpha: 0.55))),
                      const SizedBox(height: 2),
                      Text('Active',
                          style: TextStyle(
                              fontSize: 11,
                              color: on
                                  ? context.gx.ink.withValues(alpha: 0.55)
                                  : context.gx.ink.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                // Toggle Switch
                Container(
                  width: 44,
                  height: 24,
                  decoration: BoxDecoration(
                    color: on ? GixbeeTheme.accentGreen : context.gx.border,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        top: 2,
                        left: on ? 22 : 2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: on
                                ? context.gx.onAccent
                                : context.gx.ink.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _jobFeedSection(ColorScheme scheme) {
    return GoLiveJobFeed(
      jobs: _jobFeed,
      onOpenJob: _openJob,
      onDeclineJob: (job) {
        if (mounted) {
          setState(
            () => _jobFeed.removeWhere((item) => item['id'] == job['id']),
          );
        }
      },
    );
  }
}
