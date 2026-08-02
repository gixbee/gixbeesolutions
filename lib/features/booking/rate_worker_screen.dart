import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Customer rates the worker after confirming offline payment.
class RateWorkerScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final String workerName;

  const RateWorkerScreen({
    super.key,
    required this.bookingId,
    required this.workerName,
  });

  @override
  ConsumerState<RateWorkerScreen> createState() => _RateWorkerScreenState();
}

class _RateWorkerScreenState extends ConsumerState<RateWorkerScreen> {
  int _stars = 0;
  bool _submitting = false;

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      showGxSnack(context, 'Tap a star to rate', type: GxSnackType.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .submitRating(widget.bookingId, _stars);
      if (!mounted) return;
      showGxSnack(context, 'Thanks — rating submitted!',
          type: GxSnackType.success);
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGxSnack(context, 'Could not submit rating: $e',
          type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.check_circle,
                      color: GixbeeTheme.accentGreen, size: 56),
                ),
                const SizedBox(height: 20),
                Text(
                  'Job complete & paid',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.gx.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'How was ${widget.workerName}?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.gx.ink.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _stars;
                    return IconButton(
                      onPressed: () => setState(() => _stars = i + 1),
                      icon: Icon(
                        Icons.star_rounded,
                        size: 40,
                        color: filled
                            ? GixbeeTheme.accentGold
                            : context.gx.ink.withValues(alpha: 0.28),
                      ),
                    );
                  }),
                ),
                const Spacer(),
                GxButton(
                  label: 'Submit rating',
                  onTap: _submit,
                  loading: _submitting,
                  height: 56,
                  radius: 16,
                  fontSize: 16,
                  gradient: const [
                    GixbeeTheme.accentGreen,
                    GixbeeTheme.accentGreenDark,
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _goHome,
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      color: context.gx.ink.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
