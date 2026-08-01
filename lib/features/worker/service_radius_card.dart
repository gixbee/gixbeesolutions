import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Go Live setup card: **how far the pro is willing to travel**.
///
/// The dispatch fan-out (`WorkersService.getNearby`) only offers a job to a
/// pro when the customer is inside THIS radius — so a plumber who picks 5 km
/// will never be woken up for a job 30 km away. Server clamps to 1..50 km and
/// returns the authoritative value, which is what we render.
///
/// Loads GET /workers/me on mount; changing the radius PATCHes
/// /workers/me/service-radius (optimistic, reverts on failure) and takes
/// effect on the very next broadcast.
class ServiceRadiusCard extends ConsumerStatefulWidget {
  const ServiceRadiusCard({super.key});

  @override
  ConsumerState<ServiceRadiusCard> createState() => _ServiceRadiusCardState();
}

class _ServiceRadiusCardState extends ConsumerState<ServiceRadiusCard> {
  /// Must stay within the backend's MAX_DISPATCH_RADIUS_KM (50).
  static const _minKm = 1;
  static const _maxKm = 50;
  static const _defaultRadius = 10;

  int _radius = _defaultRadius;
  /// Last value confirmed by the server (or loaded) — used to skip no-op saves.
  int _persisted = _defaultRadius;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ref.read(workerRepositoryProvider).getMyWorkerProfile();
      if (!mounted) return;
      final km = (me['serviceRadiusKm'] as num?)?.toInt() ?? _defaultRadius;
      final clamped = km.clamp(_minKm, _maxKm);
      setState(() {
        _radius = clamped;
        _persisted = clamped;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Service radius load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persist(int km) async {
    final clamped = km.clamp(_minKm, _maxKm);
    if (clamped == _persisted || _saving) return;
    final previous = _persisted;
    setState(() {
      _radius = clamped;
      _saving = true;
    });
    try {
      // The server clamps — trust its answer over ours.
      final confirmed =
          await ref.read(workerRepositoryProvider).setServiceRadius(clamped);
      if (!mounted) return;
      final next = confirmed.clamp(_minKm, _maxKm);
      setState(() {
        _radius = next;
        _persisted = next;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _radius = previous;
        _persisted = previous;
        _saving = false;
      });
      showGxSnack(context, 'Could not save service area: $e',
          type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.gx.card2,
        border: Border.all(color: context.gx.border, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.social_distance_rounded,
                        size: 16, color: context.gx.accent),
                    const SizedBox(width: 8),
                    Text(
                      'SERVICE AREA',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: context.gx.ink.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    if (_saving)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Text(
                        '$_radius km',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: context.gx.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: context.gx.accent,
                    inactiveTrackColor:
                        context.gx.accent.withValues(alpha: 0.18),
                    thumbColor: context.gx.accent,
                    overlayColor:
                        context.gx.accent.withValues(alpha: 0.12),
                    valueIndicatorColor: context.gx.accent,
                    trackHeight: 3.5,
                  ),
                  child: Slider(
                    value: _radius.toDouble(),
                    min: _minKm.toDouble(),
                    max: _maxKm.toDouble(),
                    divisions: _maxKm - _minKm,
                    label: '$_radius km',
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _radius = v.round()),
                    onChangeEnd: _saving
                        ? null
                        : (v) => _persist(v.round()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_minKm km',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.gx.ink.withValues(alpha: 0.4),
                        ),
                      ),
                      Text(
                        '$_maxKm km',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.gx.ink.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will only be offered instant jobs within $_radius km of '
                  'your live location. A wider area means more jobs, but longer '
                  'travel.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: context.gx.ink.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
    );
  }
}
