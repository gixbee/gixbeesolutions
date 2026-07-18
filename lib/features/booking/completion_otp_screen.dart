import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../core/config/app_config.dart';
import 'active_job_controls.dart';
import 'collect_payment_screen.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_dialog.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';

/// Gate 2 of the live flow.
/// After the job is done, the customer shares the Completion OTP with the
/// worker. Once verified, the booking status moves from ACTIVE → COMPLETED
/// and billing hours are locked in.
class CompletionOtpScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final String workerName;

  final bool isWorker;

  const CompletionOtpScreen({
    super.key,
    required this.bookingId,
    required this.workerName,
    this.isWorker = false,
  });

  @override
  ConsumerState<CompletionOtpScreen> createState() => _CompletionOtpScreenState();
}

class _CompletionOtpScreenState extends ConsumerState<CompletionOtpScreen> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  bool _isVerifying = false;
  String? _errorMsg;
  String? _fetchedOtp; // Used by customer to display
  bool _isFetchingOtp = false; // Loading indicator for customer
  bool _isMarkingComplete = false;
  bool _hasMarkedComplete = false;
  bool _isRefreshing = false;
  int? _selectedRating;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
        AppConfig.bookingOtpLength, (_) => TextEditingController());
    _focusNodes =
        List.generate(AppConfig.bookingOtpLength, (_) => FocusNode());

    if (!widget.isWorker) {
      _fetchOtp();
    }
  }

  Future<void> _refreshOtp() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final newOtp = await ref.read(bookingRepositoryProvider).refreshCompletionOtp(widget.bookingId);
      if (mounted) {
        setState(() => _fetchedOtp = newOtp);
        showGxSnack(context, 'OTP Refreshed!', type: GxSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to refresh OTP: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _fetchOtp() async {
    setState(() => _isFetchingOtp = true);
    try {
      final b = await ref.read(bookingRepositoryProvider).getBookingById(widget.bookingId);
      if (b != null && mounted) {
        setState(() => _fetchedOtp = b['completionOtp']);
      }
    } catch (e) {
      debugPrint('Error fetching completion otp: $e');
    } finally {
      if (mounted) setState(() => _isFetchingOtp = false);
    }
  }

  Future<void> _markComplete() async {
    setState(() => _isMarkingComplete = true);
    try {
      await ref.read(bookingRepositoryProvider).markComplete(widget.bookingId);
      setState(() => _hasMarkedComplete = true);
      if (mounted) {
        showGxSnack(
          context,
          'OTP requested! Ask the customer for the completion OTP.',
          type: GxSnackType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to mark complete: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isMarkingComplete = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  Future<void> _verifyCompletion() async {
    final otp = _enteredOtp;
    if (otp.length != AppConfig.bookingOtpLength) {
      setState(() =>
          _errorMsg = 'Enter all ${AppConfig.bookingOtpLength} digits');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMsg = null;
    });

    try {
      final response = await ref.read(bookingRepositoryProvider).confirmCompletion(
            bookingId: widget.bookingId,
            otp: otp,
          );

      if (!mounted) return;

      if (response['paymentMethod'] == 'DIRECT') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CollectPaymentScreen(
              bookingId: widget.bookingId,
              // Decimal may arrive as a string — .toDouble() on it would throw.
              amount: (num.tryParse('${response['totalAmount'] ?? 0}') ?? 0)
                  .toDouble(),
              customerName: widget.workerName, // In worker view, workerName is actually the customer's name
            ),
          ),
        );
      } else {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Invalid OTP. Please try again.');
        // Shake + clear
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showSuccessDialog() {
    showGxDialog(
      context,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.check_circle, color: Colors.green, size: 56),
          ),
          const SizedBox(height: 20),
          Text(
            'Job Completed!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: context.gx.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '${widget.workerName}\'s service has been verified and marked complete. A receipt has been sent.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.gx.ink.withValues(alpha: 0.72),
              height: 1.5,
            ),
          ),
          SizedBox(height: 20),
          // Rating prompt row
          StatefulBuilder(
            builder: (ctx2, setDialogState) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return IconButton(
                  icon: Icon(
                    Icons.star_rounded,
                    size: 32,
                    color: (_selectedRating != null && i <= _selectedRating!)
                        ? Colors.amber
                        : context.gx.ink.withValues(alpha: 0.30),
                  ),
                  onPressed: () async {
                    setDialogState(() => _selectedRating = i);
                    try {
                      await ref.read(bookingRepositoryProvider).submitRating(
                            widget.bookingId,
                            i + 1,
                          );
                      if (ctx2.mounted) {
                        showGxSnack(ctx2, 'Rating saved: ${i + 1} stars',
                            type: GxSnackType.success);
                      }
                    } catch (e) {
                      debugPrint('Rating failed: $e');
                    }
                  },
                );
              }),
            ),
          ),
        ],
      ),
      actions: [
        GxDialogAction(
          'Back to Home',
          isPrimary: true,
          onTap: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(height: 24),

                // Top bar
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.handyman, size: 14, color: Colors.green),
                          SizedBox(width: 6),
                          Text(
                            'Work In Progress',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),

                const SizedBox(height: 10),

                // Live job timer + pause/resume controls + report (v126) —
                // this screen is where both roles live during ACTIVE work.
                ActiveJobControls(
                  bookingId: widget.bookingId,
                  isWorker: widget.isWorker,
                ),

                const Spacer(flex: 2),

                // Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.1),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 56,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Completion Verification',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isWorker
                    ? _hasMarkedComplete
                        ? 'Enter the completion OTP provided by the customer to finalize the job.'
                        : 'Tap "Request Completion OTP" to notify the customer that you have finished.'
                    : 'Job is complete!\nShare this OTP with ${widget.workerName} to finalize payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 36),

                // OTP display OR Input
                if (widget.isWorker)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(AppConfig.bookingOtpLength, (i) {
                      return Container(
                        width: 60,
                        height: 68,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        child: TextField(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: _controllers[i].text.isNotEmpty
                                ? context.gx.accent.withValues(alpha: 0.08)
                                : colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _errorMsg != null
                                    ? Colors.red
                                    : colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onChanged: (value) {
                            setState(() => _errorMsg = null);
                            if (value.isNotEmpty &&
                                i < AppConfig.bookingOtpLength - 1) {
                              _focusNodes[i + 1].requestFocus();
                            } else if (value.isEmpty && i > 0) {
                              _focusNodes[i - 1].requestFocus();
                            }
                            // No auto-submit
                          },
                        ),
                      );
                    }),
                  )
                else
                  // Customer view: Show the code
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: _isFetchingOtp
                            ? SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(strokeWidth: 3),
                              )
                            : Text(
                                _fetchedOtp ?? '• • • •',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 16,
                                  color: Colors.green,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                      if (_fetchedOtp == null && !_isFetchingOtp)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Waiting for worker to mark job complete...',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      GxPressable(
                        onTap: _isRefreshing || _isFetchingOtp ? null : _refreshOtp,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _isRefreshing
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: context.gx.accent))
                                  : Icon(Icons.refresh,
                                      size: 18,
                                      color: context.gx.accent),
                              SizedBox(width: 6),
                              Text(
                                'Refresh OTP',
                                style: TextStyle(
                                  color: context.gx.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                // Error message
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],

                const Spacer(flex: 3),

                // Verify button
                if (widget.isWorker)
                  _hasMarkedComplete
                      ? GxButton(
                          label: _isVerifying
                              ? 'Verifying...'
                              : 'Submit OTP to Complete Job',
                          icon: Icons.check_circle_outline,
                          onTap: _isVerifying ? null : _verifyCompletion,
                          loading: _isVerifying,
                          gradient: const [Colors.green, Colors.green],
                          accent: Colors.green,
                          height: 56,
                          fontSize: 16,
                        )
                      : GxButton(
                          label: _isMarkingComplete
                              ? 'Requesting...'
                              : 'Request Completion OTP',
                          icon: Icons.task_alt,
                          onTap: _isMarkingComplete ? null : _markComplete,
                          loading: _isMarkingComplete,
                          gradient: const [Colors.green, Colors.green],
                          accent: Colors.green,
                          height: 56,
                          fontSize: 16,
                        )
                else
                  const Text('Waiting for worker to verify completion...', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),

                const SizedBox(height: 16),

                // Dispute link
                GxPressable(
                  onTap: _showDisputeDialog,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Report an issue with this job',
                      style: TextStyle(
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
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

  void _showDisputeDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Report an Issue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('What went wrong? Our team will review your report.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            _disputeOption('Worker didn\'t show up'),
            _disputeOption('Unprofessional behavior'),
            _disputeOption('Work not completed as expected'),
            _disputeOption('Payment / Pricing issue'),
            const SizedBox(height: 24),
            GxButton(
              label: 'Cancel',
              onTap: () => Navigator.pop(ctx),
              filled: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _disputeOption(String reason) {
    return ListTile(
      title: Text(reason),
      leading: const Icon(Icons.report_problem_outlined, color: Colors.orange),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () async {
        Navigator.pop(context);
        try {
          await ref.read(bookingRepositoryProvider).reportDispute(widget.bookingId, reason);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dispute filed: $reason.\nOur support team will contact you shortly.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            showGxSnack(context, 'Failed to submit dispute: $e',
                type: GxSnackType.error);
          }
        }
      },
    );
  }
}

