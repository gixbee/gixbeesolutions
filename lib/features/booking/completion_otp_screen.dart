import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../core/config/app_config.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP Refreshed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh OTP: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job marked as complete! Ask customer for completion OTP.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark complete: $e')),
        );
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
      await ref.read(bookingRepositoryProvider).confirmCompletion(
            bookingId: widget.bookingId,
            otp: otp,
          );

      if (!mounted) return;
      _showSuccessDialog();
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              'Job Completed!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.workerName}\'s service has been verified and marked complete. A receipt has been sent.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Rating prompt row
            StatefulBuilder(
              builder: (context, setDialogState) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      Icons.star_rounded,
                      size: 32,
                      color: (_selectedRating != null && i <= _selectedRating!) 
                          ? Colors.amber : Colors.grey.shade400,
                    ),
                    onPressed: () async {
                      setDialogState(() => _selectedRating = i);
                      try {
                        await ref.read(bookingRepositoryProvider).submitRating(
                          widget.bookingId, i + 1
                        );
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Rating saved: ${i + 1} stars')),
                          );
                        }
                      } catch (e) {
                         debugPrint('Rating failed: $e');
                      }
                    },
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).popUntil((route) => route.isFirst),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
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
                const SizedBox(height: 24),

                // Top bar
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
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
                        ? 'Job finished! Ask for the completion OTP\nand enter it below to receive payment.'
                        : 'Tap "I\'ve Finished" when the work is\nfully completed.'
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
                                ? colorScheme.primary.withValues(alpha: 0.08)
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
                            ? const SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(strokeWidth: 3),
                              )
                            : Text(
                                _fetchedOtp ?? '• • • •',
                                style: const TextStyle(
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
                      TextButton.icon(
                        onPressed: _isRefreshing || _isFetchingOtp ? null : _refreshOtp,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh OTP'),
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
                      ? SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _isVerifying ? null : _verifyCompletion,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: _isVerifying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              _isVerifying ? 'Verifying...' : 'Confirm Job Complete',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        )
                      : SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _isMarkingComplete ? null : _markComplete,
                            icon: _isMarkingComplete
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.task_alt),
                            label: Text(
                              _isMarkingComplete ? 'Confirming...' : 'I\'ve Finished the Job',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        )
                else
                  const Text('Waiting for worker to verify completion...', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),

                const SizedBox(height: 16),

                // Dispute link
                TextButton(
                  onPressed: () {
                    _showDisputeDialog();
                  },
                  child: Text(
                    'Report an issue with this job',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 13,
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
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
      onTap: () {
        Navigator.pop(context);
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
      },
    );
  }
}

