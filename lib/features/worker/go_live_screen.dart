import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../services/location_service.dart';
import '../../services/socket_service.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../jobs/register_pro_screen.dart';
import '../booking/incoming_job_screen.dart';
import 'worker_languages_card.dart';
import 'service_radius_card.dart';

/// Go-Live dashboard: skills + per-service activation + earnings summary.
/// `GET /workers/me/dashboard` — refreshed after every live toggle.
final goLiveDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(workerRepositoryProvider).getGoLiveDashboard();
});

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
  bool _toggling = false;

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
  Timer? _locationHeartbeat;
  bool _presenceStarted = false;

  @override
  void initState() {
    super.initState();
    _socketSub = ref.read(socketServiceProvider).notifications.listen(_onSocketEvent);
    // If already live when opening this screen, start GPS presence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(workerLiveStateProvider)) {
        unawaited(_startTicker(reset: false));
        unawaited(_ensureLivePresence());
        unawaited(_refreshPendingFeed());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _locationHeartbeat?.cancel();
    _socketSub?.cancel();
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
            setState(() => _jobFeed.removeWhere((j) => j['id']?.toString() == targetId));
          }
        }
      }
      unawaited(_refreshPendingFeed());
    }
  }

  Future<void> _refreshPendingFeed() async {
    if (!mounted || !ref.read(workerLiveStateProvider)) return;
    try {
      final pending = await ref.read(bookingRepositoryProvider).getPendingBookings();
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
        await storage.write(key: 'worker_live_since', value: _liveSince!.toIso8601String());
      }
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _liveSince == null) return;
      setState(() => _elapsed = DateTime.now().difference(_liveSince!));
      if (timer.tick % 5 == 0) {
        unawaited(_refreshPendingFeed());
      }
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

  Future<void> _ensureLivePresence() async {
    if (_presenceStarted) return;
    final user = await ref.read(currentUserProvider.future);
    if (user == null || !mounted) return;
    _presenceStarted = true;

    final socket = ref.read(socketServiceProvider);
    // Socket is already connected in MainWrapper with the JWT — do not
    // reconnect with the user id (that would break auth).
    socket.joinUserRoom(user.id);
    socket.startLivePresenceStream(user.id);

    // HTTP heartbeat so Instant Help still matches if the socket is down.
    _locationHeartbeat?.cancel();
    Future<void> pushLoc() async {
      try {
        final pos =
            await ref.read(locationServiceProvider).getCurrentPosition();
        if (pos == null) return;
        await ref.read(workerRepositoryProvider).updateMyLocation(
              lat: pos.latitude,
              lng: pos.longitude,
            );
      } catch (_) {}
    }

    unawaited(pushLoc());
    _locationHeartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(pushLoc()),
    );
  }

  void _stopLivePresence() {
    _presenceStarted = false;
    _locationHeartbeat?.cancel();
    _locationHeartbeat = null;
    ref.read(socketServiceProvider).stopLocationStream();
  }

  Future<void> _toggle() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      // Capture GPS before going live so Instant Help can match this worker.
      double? lat;
      double? lng;
      final currentlyLive = ref.read(workerLiveStateProvider);
      if (!currentlyLive) {
        final pos =
            await ref.read(locationServiceProvider).getCurrentPosition();
        lat = pos?.latitude;
        lng = pos?.longitude;
      }

      final result = await ref.read(workerRepositoryProvider).goLiveToggle(
            lat: lat,
            lng: lng,
          );
      ref.read(workerLiveStateProvider.notifier).state = result.isActive;
      ref.invalidate(goLiveDashboardProvider);

      if (result.isActive) {
        unawaited(_startTicker(reset: true));
        await _ensureLivePresence();
        unawaited(_refreshPendingFeed());
      } else {
        unawaited(_stopTicker());
        _jobFeed.clear();
        _stopLivePresence();
      }
      if (mounted) {
        _toast(result.message, error: false);
        if (result.isActive && lat == null && !currentlyLive) {
          _toast(
            'Location unavailable — enable GPS so customers can find you.',
            error: true,
          );
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? 'Could not update Go-Live status')
          : 'Could not update Go-Live status';
      if (mounted) _toast(msg, error: true);
    } catch (_) {
      if (mounted) _toast('Could not update Go-Live status', error: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _toast(String msg, {required bool error}) {
    showGxSnack(
      context,
      msg,
      type: error ? GxSnackType.error : GxSnackType.success,
    );
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingJobScreen(bookingData: job),
        fullscreenDialog: true,
      ),
    );
    if (mounted) {
      setState(() => _jobFeed.removeWhere((j) => j['id'] == job['id']));
      unawaited(_refreshPendingFeed());
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
    if (serverLive) {
      if (_liveSince == null) unawaited(_startTicker(reset: false));
      unawaited(_ensureLivePresence());
      unawaited(_refreshPendingFeed());
    } else {
      unawaited(_stopTicker());
      _jobFeed.clear();
      _stopLivePresence();
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
        title: Text('Go Live', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.gx.ink)),
        centerTitle: true,
        actions: [
          if (isLive)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _fmt(_elapsed),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: GixbeeTheme.accentGreen, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text('Could not load your profile', style: TextStyle(color: context.gx.ink))),
        data: (user) {
          if (user == null || !user.isWorker) {
            return _NotAWorker(scheme: scheme);
          }
          final dashAsync = ref.watch(goLiveDashboardProvider);
          final dash = dashAsync.asData?.value;
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
                      : _buildSetupView(scheme, user, dash, dashAsync.isLoading),
                ),
              ),
              // Sticky Go Live / Offline Button
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildStickyFooter(isLive),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSetupView(ColorScheme scheme, dynamic user, Map<String, dynamic>? dash, bool isLoading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // padding for sticky footer
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.gx.onAccent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.gx.ink)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.verified_user, size: 12, color: GixbeeTheme.accentGreen),
                          const SizedBox(width: 5),
                          Text('Aadhaar Verified', style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55))),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 12, color: context.gx.accent),
                          const SizedBox(width: 5),
                          Text('Auto-updating GPS', style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55))),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('4.8', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: GixbeeTheme.accentGold)),
                    Text('★ rating', style: TextStyle(fontSize: 10, color: GixbeeTheme.accentGold)),
                    const SizedBox(height: 2),
                    Text('${dash?['earnings']?['jobsCompleted'] ?? 0} jobs', style: TextStyle(fontSize: 10, color: context.gx.ink.withValues(alpha: 0.55))),
                  ],
                ),
              ],
            ),
          ),

          // WALLET STATUS
          Container(
            decoration: BoxDecoration(
              color: const Color(0x0F10B981),
              border: Border.all(color: const Color(0x3310B981), width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0x1F10B981),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet, size: 18, color: GixbeeTheme.accentGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gixbee Wallet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.gx.ink)),
                      const SizedBox(height: 2),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 11, color: context.gx.ink.withValues(alpha: 0.55), fontFamily: 'Inter'),
                          children: [
                            const TextSpan(text: '₹12 deducted per job · Balance: '),
                            TextSpan(text: '₹100', style: const TextStyle(fontWeight: FontWeight.w700, color: GixbeeTheme.accentGreen)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1A10B981),
                    border: Border.all(color: const Color(0x3310B981)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Ready', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GixbeeTheme.accentGreen)),
                ),
              ],
            ),
          ),

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
                        builder: (_) => const RegisterProScreen()),
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
                    color: GixbeeTheme.accentPurple,
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
                  accent: GixbeeTheme.accentPurple,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterProScreen()),
                    );
                    if (!mounted) return;
                    ref.invalidate(goLiveDashboardProvider);
                  },
                ),
              ),
          ] else if (isLoading) ...[
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
          ],

          const SizedBox(height: 14),
          // v126 language matching: customers can require languages; only
          // pros with an overlap get those broadcasts.
          Text('LANGUAGES I SPEAK', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.gx.ink.withValues(alpha: 0.55), letterSpacing: 1.2)),
          const SizedBox(height: 10),
          const WorkerLanguagesCard(),

          const SizedBox(height: 14),
          // How far this pro will travel — jobs outside it are never broadcast
          // to them (WorkersService.getNearby enforces it).
          const ServiceRadiusCard(),

          const SizedBox(height: 14),
          Text('YOUR LOCATION', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.gx.ink.withValues(alpha: 0.55), letterSpacing: 1.2)),
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
                  child: Icon(Icons.location_on, size: 18, color: context.gx.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.gx.ink)),
                      const SizedBox(height: 2),
                      Text('GPS: Auto-updating · Accurate', style: TextStyle(fontSize: 11, color: context.gx.ink.withValues(alpha: 0.55))),
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

  Widget _buildLiveView(ColorScheme scheme, dynamic user, Map<String, dynamic>? dash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LIVE HERO
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [context.gx.bg, context.gx.card],
            ),
            border: Border(bottom: BorderSide(color: Color(0x2210B981))),
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
                      color: const Color(0x1A10B981),
                    ),
                  ),
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x3310B981),
                    ),
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GixbeeTheme.accentGreen,
                      boxShadow: [
                        BoxShadow(color: Color(0x6610B981), blurRadius: 20),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.radar, color: context.gx.onAccent, size: 36),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Looking for nearby jobs...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.gx.ink)),
              const SizedBox(height: 4),
              Text('Keep app open. You will be notified instantly.', style: TextStyle(fontSize: 13, color: context.gx.ink.withValues(alpha: 0.55))),
            ],
          ),
        ),

        if (dash != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildLiveStatCard('Jobs Today', '${dash['earnings']?['jobsCompleted'] ?? 0}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLiveStatCard('Earned', '₹${dash['earnings']?['today'] ?? 0}'),
                ),
              ],
            ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.gx.border),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.gx.ink)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55))),
        ],
      ),
    );
  }

  Widget _buildStickyFooter(bool isLive) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gx.bg,
        border: Border(top: BorderSide(color: context.gx.border)),
      ),
      child: GestureDetector(
        onTap: _toggling ? null : _toggle,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLive 
                ? [const Color(0xFFDC2626), const Color(0xFF991B1B)] 
                : [const Color(0xFF059669), const Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isLive ? const Color(0xFFDC2626) : const Color(0xFF10B981)).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: _toggling
              ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: context.gx.onAccent, strokeWidth: 3))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isLive ? Icons.power_settings_new : Icons.bolt, color: context.gx.onAccent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      isLive ? 'Go Offline' : 'Go Live Now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.gx.onAccent),
                    ),
                  ],
                ),
        ),
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
          ? (e.response?.data['message']?.toString() ?? 'Could not update services')
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
              border: Border.all(color: on ? context.gx.accent : context.gx.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: on ? context.gx.accent.withValues(alpha: 0.2) : context.gx.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(on ? Icons.bolt : Icons.design_services, size: 18, color: on ? context.gx.accent : context.gx.ink.withValues(alpha: 0.55)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(skill, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? context.gx.ink : context.gx.ink.withValues(alpha: 0.55))),
                      const SizedBox(height: 2),
                      Text('Active', style: TextStyle(fontSize: 11, color: on ? context.gx.ink.withValues(alpha: 0.55) : context.gx.ink.withValues(alpha: 0.55))),
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
                            color: on ? context.gx.onAccent : context.gx.ink.withValues(alpha: 0.55),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('INCOMING JOBS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.gx.ink.withValues(alpha: 0.55), letterSpacing: 1.2)),
        const SizedBox(height: 10),
        if (_jobFeed.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: context.gx.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.gx.border),
            ),
            child: Column(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.gx.accent)),
                const SizedBox(height: 10),
                Text('Waiting for job requests...', style: TextStyle(color: context.gx.ink.withValues(alpha: 0.55), fontSize: 13)),
              ],
            ),
          )
        else
          ..._jobFeed.map((job) => _jobCard(scheme, job)),
      ],
    );
  }

  Widget _jobCard(ColorScheme scheme, Map<String, dynamic> job) {
    final skill = (job['skill'] ?? 'Service').toString();
    final customer = (job['customer_name'] ?? job['customerName'] ?? 'Customer').toString();
    final location = (job['serviceLocation'] ?? '').toString();
    final amount = (job['amount'] is num) ? (job['amount'] as num).toDouble() : 0.0;
    final isHourly =
        (job['type'] ?? 'INSTANT').toString().toUpperCase() == 'INSTANT';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.accent.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.gx.accent.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: context.gx.accentGradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.flash_on, color: context.gx.onAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(skill, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.gx.ink)),
                    const SizedBox(height: 2),
                    Text(customer, style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55))),
                  ],
                ),
              ),
              if (amount > 0)
                Text(
                  isHourly
                      ? '₹${amount.toStringAsFixed(0)}/hr'
                      : '₹${amount.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: GixbeeTheme.accentGold),
                ),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.gx.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: context.gx.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFDDDDDD)))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'Decline',
                  filled: false,
                  onTap: () {
                    if (mounted) setState(() => _jobFeed.removeWhere((j) => j['id'] == job['id']));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GxButton(
                  label: 'View Job',
                  gradient: const [Color(0xFF059669), Color(0xFF10B981)],
                  onTap: () => _openJob(job),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

class _NotAWorker extends StatelessWidget {
  final ColorScheme scheme;
  const _NotAWorker({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Become a Gixbee Pro',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Register your skills to start receiving instant jobs and go live.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 20),
            GxButton(
              label: 'Register as Pro',
              icon: Icons.assignment_ind_outlined,
              expand: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterProScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
