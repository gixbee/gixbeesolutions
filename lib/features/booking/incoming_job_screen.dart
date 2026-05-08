import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/booking_repository.dart';

/// Shown as a full-screen modal when the worker receives job requests.
/// Handles a QUEUE of multiple simultaneous requests from different customers.
/// Worker can Accept one (auto-declines others) or Decline individual ones.
class IncomingJobScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> bookingData;

  const IncomingJobScreen({super.key, required this.bookingData});

  @override
  ConsumerState<IncomingJobScreen> createState() => _IncomingJobScreenState();
}

class _IncomingJobScreenState extends ConsumerState<IncomingJobScreen> {
  // ── All pending requests for this worker ──────────────────────────────────
  late List<Map<String, dynamic>> _requests;
  int _currentIndex = 0;

  // ── Per-request state ─────────────────────────────────────────────────────
  int _secondsRemaining = AppConfig.jobAcceptTimeoutSeconds;
  Timer? _timer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _requests = [widget.bookingData];
    _startTimer();
    _pollForMoreRequests();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsRemaining = AppConfig.jobAcceptTimeoutSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
        _autoDeclineCurrent();
      }
    });
  }

  void _resetTimerForNewRequest() {
    _startTimer();
  }

  // ── Poll for more requests while screen is open ───────────────────────────

  Future<void> _pollForMoreRequests() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    try {
      final all = await ref.read(bookingRepositoryProvider).getPendingBookings();
      if (!mounted) return;
      setState(() {
        final existingIds = _requests.map((r) => r['id']).toSet();
        for (final r in all) {
          if (!existingIds.contains(r['id'])) {
            _requests.add(r);
          }
        }
      });
    } catch (_) {}
  }

  // ── Accept ────────────────────────────────────────────────────────────────

  Future<void> _accept() async {
    if (_isProcessing || _requests.isEmpty) return;
    setState(() => _isProcessing = true);
    _timer?.cancel();

    final current = _requests[_currentIndex];
    final bookingId = current['id'] as String?;

    try {
      if (bookingId == null) throw Exception('Missing booking ID');
      await ref.read(bookingRepositoryProvider).acceptBooking(bookingId);

      if (!mounted) return;
      // Backend auto-cancels all other pending bookings for this worker
      Navigator.pop(context, {'accepted': true, 'bookingId': bookingId});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Job Accepted! Head to the customer location.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _startTimer();
    }
  }

  // ── Decline current request ───────────────────────────────────────────────

  Future<void> _declineCurrent() async {
    _timer?.cancel();
    setState(() => _isProcessing = true);

    final bookingId = _requests[_currentIndex]['id'] as String?;
    try {
      if (bookingId != null) {
        await ref.read(bookingRepositoryProvider).rejectBooking(bookingId);
      }
    } catch (e) {
      debugPrint('[IncomingJob] Decline failed: $e');
    }

    _removeCurrentAndAdvance();
  }

  Future<void> _autoDeclineCurrent() async {
    final bookingId = _requests[_currentIndex]['id'] as String?;
    try {
      if (bookingId != null) {
        await ref.read(bookingRepositoryProvider).rejectBooking(bookingId);
      }
    } catch (_) {}
    _removeCurrentAndAdvance(isTimeout: true);
  }

  void _removeCurrentAndAdvance({bool isTimeout = false}) {
    if (!mounted) return;
    setState(() {
      _requests.removeAt(_currentIndex);
      _isProcessing = false;

      if (_requests.isEmpty) {
        // No more requests — close the screen
        Navigator.pop(context, {'accepted': false});
        return;
      }

      // Clamp index if we were at the last item
      if (_currentIndex >= _requests.length) {
        _currentIndex = _requests.length - 1;
      }

      // Start fresh timer for the next request
      _resetTimerForNewRequest();

      if (isTimeout) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⏱ Request from ${_requests[_currentIndex]['customer_name'] ?? 'customer'} timed out. Moving to next.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // ── Navigate between queued requests ─────────────────────────────────────

  void _goToRequest(int index) {
    setState(() {
      _currentIndex = index;
      _resetTimerForNewRequest();
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_requests.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;
    final current = _requests[_currentIndex];
    final customerName = current['customer_name'] as String? ?? 'New Customer';
    final skill = current['skill'] as String? ?? 'General Help';
    final location = current['serviceLocation'] as String? ?? 'Nearby';
    final amount = (current['amount'] as num?)?.toDouble() ?? 0.0;
    final totalRequests = _requests.length;
    final timerFraction =
        _secondsRemaining / AppConfig.jobAcceptTimeoutSeconds;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  // Close
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.pop(context, {'accepted': false}),
                  ),
                  const Spacer(),
                  // Queue indicator badge
                  if (totalRequests > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$totalRequests requests waiting',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on, color: Colors.orange, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'INSTANT REQUEST',
                            style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ── Queue tabs (visible when multiple requests) ─────────────────
            if (totalRequests > 1) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: List.generate(totalRequests, (i) {
                    final isActive = i == _currentIndex;
                    final req = _requests[i];
                    return GestureDetector(
                      onTap: () => _goToRequest(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          req['customer_name'] as String? ?? 'Request ${i + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : null,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],

            const Spacer(),

            // ── Countdown ring ──────────────────────────────────────────────
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: timerFraction,
                    strokeWidth: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: _secondsRemaining > 20
                        ? Colors.green
                        : _secondsRemaining > 10
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_secondsRemaining',
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'seconds',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Customer info ───────────────────────────────────────────────
            Text(
              customerName,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'needs a $skill',
              style: TextStyle(
                  fontSize: 17, color: colorScheme.secondary),
            ),

            const SizedBox(height: 28),

            // ── Details cards ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  _DetailCard(
                    icon: Icons.location_on_rounded,
                    label: 'Location',
                    value: location,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _DetailCard(
                    icon: Icons.payments_rounded,
                    label: 'Estimated Earnings',
                    value: '₹${amount.toStringAsFixed(0)}',
                    color: Colors.green,
                  ),
                  if (totalRequests > 1) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      icon: Icons.info_outline_rounded,
                      label: 'Queue note',
                      value:
                          'Accepting this cancels your other ${totalRequests - 1} pending request${totalRequests > 2 ? 's' : ''}',
                      color: Colors.orange,
                    ),
                  ],
                ],
              ),
            ),

            const Spacer(),

            // ── Action buttons ──────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Row(
                children: [
                  // Decline button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _declineCurrent,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        foregroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        totalRequests > 1 ? 'Skip' : 'Decline',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Accept button
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _isProcessing ? null : _accept,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'Accept Job',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
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
  }
}

// ── Detail Card Widget ──────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
