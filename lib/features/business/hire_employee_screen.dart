import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/matching_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'hiring_requests_screen.dart';

/// Employer Smart Hiring form: estimate → pay → start 24 h matching.
class HireEmployeeScreen extends ConsumerStatefulWidget {
  const HireEmployeeScreen({super.key});

  @override
  ConsumerState<HireEmployeeScreen> createState() => _HireEmployeeScreenState();
}

class _HireEmployeeScreenState extends ConsumerState<HireEmployeeScreen> {
  final _jobTypeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController(text: '25000');
  final _expCtrl = TextEditingController(text: '0');
  final _skillCtrl = TextEditingController();
  final Set<String> _skills = {};
  int _vacancies = 1;
  int? _estimated;
  int? _fee;
  int _creditBalance = 0;
  bool _estimating = false;
  bool _submitting = false;
  Timer? _debounce;
  Razorpay? _razorpay;

  @override
  void initState() {
    super.initState();
    _loadCredit();
    _salaryCtrl.addListener(_scheduleEstimate);
    _jobTypeCtrl.addListener(_scheduleEstimate);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _razorpay?.clear();
    _jobTypeCtrl.dispose();
    _locationCtrl.dispose();
    _salaryCtrl.dispose();
    _expCtrl.dispose();
    _skillCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCredit() async {
    try {
      final c =
          await ref.read(matchingRepositoryProvider).hiringCreditBalance();
      if (!mounted) return;
      setState(() => _creditBalance = (c['balance'] as num?)?.round() ?? 0);
    } catch (_) {}
  }

  void _scheduleEstimate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _estimate);
  }

  Future<void> _estimate() async {
    final jobType = _jobTypeCtrl.text.trim();
    final salary = num.tryParse(_salaryCtrl.text.trim());
    if (jobType.isEmpty || salary == null || salary <= 0) {
      setState(() {
        _estimated = null;
        _fee = null;
      });
      return;
    }
    setState(() => _estimating = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final est = await repo.estimate(
        jobType: jobType,
        salary: salary,
        location: _locationCtrl.text.trim(),
        experienceMin: int.tryParse(_expCtrl.text.trim()) ?? 0,
        skills: _skills.toList(),
      );
      final pricing = await repo.pricing();
      final tiers = (pricing['tiers'] as List?) ?? [];
      int fee = 49;
      for (final t in tiers) {
        final maxV = (t['maxVacancies'] as num?)?.toInt() ?? 1;
        if (_vacancies <= maxV) {
          fee = (t['fee'] as num?)?.toInt() ?? fee;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _estimated = (est['estimated'] as num?)?.toInt() ?? 0;
        _fee = fee;
        _estimating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _estimating = false);
    }
  }

  Map<String, dynamic> _draft() => {
        'jobType': _jobTypeCtrl.text.trim(),
        'skills': _skills.toList(),
        'location': _locationCtrl.text.trim(),
        'salaryOffered': num.parse(_salaryCtrl.text.trim()),
        'experienceMinYears': int.tryParse(_expCtrl.text.trim()) ?? 0,
        'vacancies': _vacancies,
      };

  Future<void> _submit() async {
    if (_jobTypeCtrl.text.trim().isEmpty) {
      showGxSnack(context, 'Job Type is required', type: GxSnackType.error);
      return;
    }
    if (num.tryParse(_salaryCtrl.text.trim()) == null) {
      showGxSnack(context, 'Enter a valid salary', type: GxSnackType.error);
      return;
    }
    setState(() => _submitting = true);
    final repo = ref.read(matchingRepositoryProvider);
    try {
      final result = await repo.createRequest(_draft());
      if (result['needsPayment'] == true) {
        await _payAndCreate(_draft());
        return;
      }
      if (!mounted) return;
      showGxSnack(context, 'Matching started — 24 h guarantee',
          type: GxSnackType.success);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HiringRequestsScreen()),
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, _friendlyPayMessage(msg),
          type: GxSnackType.error);
      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
      setState(() => _submitting = false);
    }
  }

  String _friendlyPayMessage(String? msg) {
    final m = (msg ?? '').toLowerCase();
    if (m.contains('not configured') ||
        m.contains('not available') ||
        m.contains('needsapikey') ||
        m.contains('gateway')) {
      return 'Payment gateway is not configured yet — matching itself is fine once Razorpay keys are set on the server.';
    }
    if (m.contains('verif')) {
      return msg ??
          'Your hiring business must be verified by admin before Hire Employee.';
    }
    return msg ?? 'Could not start hiring';
  }

  Future<void> _payAndCreate(Map<String, dynamic> draft) async {
    try {
      final order = await ref
          .read(matchingRepositoryProvider)
          .createHiringMatchOrder(draft);
      if (order['needsApiKey'] == true) {
        if (!mounted) return;
        showGxSnack(
          context,
          'Payment gateway is not configured yet — matching itself is fine once Razorpay keys are set on the server.',
          type: GxSnackType.error,
        );
        setState(() => _submitting = false);
        return;
      }
      final user = ref.read(currentUserProvider).value;
      _razorpay ??= Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaid)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPayFail)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
      _razorpay!.open({
        'key': order['keyId'] ?? AppConfig.razorpayKey,
        'amount': order['amount'],
        'order_id': order['orderId'],
        'currency': order['currency'] ?? 'INR',
        'name': AppConfig.appName,
        'description':
            'Smart Hiring — 24 h guarantee (₹${order['amountDue'] ?? ''})',
        'timeout': AppConfig.paymentTimeoutSeconds,
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
      });
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, _friendlyPayMessage(msg),
          type: GxSnackType.error);
      setState(() => _submitting = false);
    }
  }

  void _onPaid(PaymentSuccessResponse _) {
    if (!mounted) return;
    showGxSnack(context, 'Payment received — starting matching…',
        type: GxSnackType.success);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HiringRequestsScreen()),
      );
    });
  }

  void _onPayFail(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _submitting = false);
    showGxSnack(context, 'Payment failed: ${r.message ?? 'try again'}',
        type: GxSnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    final creditApplied =
        (_fee != null) ? (_creditBalance.clamp(0, _fee!)) : 0;
    final due =
        (_fee != null) ? (_fee! - creditApplied).clamp(0, _fee!) : null;

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        title: const Text('Hire Employee'),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HiringRequestsScreen()),
            ),
            child: const Text('My requests'),
          ),
        ],
      ),
      body: DribbbleBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(
              'Pay for Smart Matching — candidates come from Find a Job → Job Types. '
              'Only interested candidates reach you. 24 Hour Hiring Guarantee.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.gx.ink.withValues(alpha: 0.55),
              ),
            ),
            if (_creditBalance > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Hiring credit available: ₹$_creditBalance',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: GixbeeTheme.accentGreen,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _jobTypeCtrl,
              decoration: const InputDecoration(
                labelText: 'Job Type',
                hintText: 'e.g. Cashier',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(labelText: 'Location'),
              onChanged: (_) => _scheduleEstimate(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salaryCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Salary offered (₹/month)',
                helperText: 'Slider estimate uses this amount',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Min experience (years)'),
              onChanged: (_) => _scheduleEstimate(),
            ),
            const SizedBox(height: 12),
            Text('Vacancies: $_vacancies',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: context.gx.ink)),
            Slider(
              value: _vacancies.toDouble(),
              min: 1,
              max: 25,
              divisions: 24,
              label: '$_vacancies',
              onChanged: (v) {
                setState(() => _vacancies = v.round());
                _scheduleEstimate();
              },
            ),
            const SizedBox(height: 8),
            Text('Skills',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: context.gx.ink)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _skillCtrl,
                    decoration: const InputDecoration(hintText: 'Add skill'),
                    onSubmitted: (_) {
                      final s = _skillCtrl.text.trim();
                      if (s.isEmpty) return;
                      setState(() {
                        _skills.add(s);
                        _skillCtrl.clear();
                      });
                      _scheduleEstimate();
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final s = _skillCtrl.text.trim();
                    if (s.isEmpty) return;
                    setState(() {
                      _skills.add(s);
                      _skillCtrl.clear();
                    });
                    _scheduleEstimate();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final s in _skills)
                  InputChip(
                    label: Text(s),
                    onDeleted: () {
                      setState(() => _skills.remove(s));
                      _scheduleEstimate();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.gx.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.gx.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _estimating
                        ? 'Estimating matches…'
                        : _estimated == null
                            ? 'Enter job type + salary for an estimate'
                            : '≈ $_estimated matching candidates',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink,
                    ),
                  ),
                  if (_fee != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      creditApplied > 0
                          ? 'Fee ₹$_fee · credit −₹$creditApplied · pay ₹$due'
                          : 'Match fee: ₹$_fee (24 h guarantee)',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      'Target: ~${_vacancies * 3} interested candidates',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.gx.ink.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            GxButton(
              label: _submitting
                  ? 'Starting…'
                  : due == 0
                      ? 'Start matching (use credit)'
                      : 'Pay & start matching',
              accent: GixbeeTheme.accentBlue,
              onTap: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
