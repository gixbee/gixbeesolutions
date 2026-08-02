import 'package:flutter/material.dart';
import '../utils/api_error_message.dart';
import 'gx_empty.dart';

/// Full-screen / centered network failure with a Retry CTA.
///
/// Use for provider/list load failures — not for session expiry (that
/// tears down [MainWrapper] and goes to Welcome).
class GxNetworkError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  final String? title;
  final Color? accent;

  const GxNetworkError({
    super.key,
    required this.onRetry,
    this.error,
    this.title,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GxEmptyState(
      icon: Icons.wifi_off_rounded,
      title: title ?? 'Something went wrong',
      message: apiErrorMessage(
        error ?? Exception('network'),
        fallback:
            'Please check your network or try again later.',
      ),
      accent: accent,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
