import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/matching_repository.dart';
import '../jobs/hiring_catalog.dart';
import '../jobs/hiring_master_picker.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'hiring_requests_screen.dart';

final _catalogueProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(matchingRepositoryProvider).hiringCatalogue();
});

/// Employer Smart Hiring wizard (v147 `hj1`–`hj4`): estimate → pay → 24 h match.
///
/// Steps mirror the prototype — same POST body to `/hiring/match/requests`.
class HireEmployeeScreen extends ConsumerStatefulWidget {
  const HireEmployeeScreen({super.key, this.businessId});
  final String? businessId;

  @override
  ConsumerState<HireEmployeeScreen> createState() => _HireEmployeeScreenState();
}

class _HireEmployeeScreenState extends ConsumerState<HireEmployeeScreen> {
  static const _stepLabels = ['Type & sector', 'Position', 'Requirements', 'Location & pay', 'Review'];

  int _step = 0;

  String? _employmentType; // FT | PT | INTERN | CONTRACT
  String? _sectorId;
  String? _positionId;
  String? _positionLabel;
  String? _qualificationId;
  String _salaryPeriod = 'MONTHLY';
  String _workMode = 'ONSITE';
  String _typeLabel = 'Type';
  String _fieldPattern = 'typeChips';
  List<Map<String, dynamic>> _specializationChoices = [];
  List<Map<String, dynamic>> _skillChoices = [];
  bool _showMoreSkills = false;
  String? _locationId;
  String? _locationLabel;
  final List<String> _specializationIds = [];
  final List<String> _skillIds = [];
  bool _qualificationRequired = false;
  String? _category;
  final _jobTypeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _salaryMinCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController(text: '25000');
  final _expCtrl = TextEditingController(text: '0');
  final _descriptionCtrl = TextEditingController();
  final Set<String> _skills = {};
  int _vacancies = 1;
  bool _salaryNegotiable = false;

  int? _estimated;
  int? _fee;
  int _creditBalance = 0;
  bool _estimating = false;
  String? _estimateError;
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
    _salaryMinCtrl.dispose();
    _expCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  String get _resolvedJobType {
    final custom = _jobTypeCtrl.text.trim();
    if (custom.isNotEmpty) return custom;
    return _category ?? '';
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
    final jobType = _resolvedJobType;
    final salaryMax = num.tryParse(_salaryCtrl.text.trim());
    if (jobType.isEmpty || salaryMax == null || salaryMax <= 0) {
      setState(() {
        _estimated = null;
        _fee = null;
      });
      return;
    }
    final salaryMin = num.tryParse(_salaryMinCtrl.text.trim());
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final est = await repo.estimate(
        jobType: jobType,
        salary: salaryMax,
        salaryMin: salaryMin,
        salaryMax: salaryMax,
        salaryNegotiable: _salaryNegotiable,
        employmentType: _employmentType,
        location: _locationCtrl.text.trim(),
        experienceMin: int.tryParse(_expCtrl.text.trim()) ?? 0,
        skills: _skills.toList(),
        positionId: _positionId,
        specializationIds: _specializationIds,
        skillIds: _skillIds,
        qualificationId: _qualificationId,
        qualificationRequired: _qualificationRequired,
        salaryPeriod: _salaryPeriod,
        locationId: _locationId,
        workMode: _workMode,
      );
      final pricing = await repo.pricing();
      final tiers = (pricing['tiers'] as List?) ?? [];
      var fee = 49;
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
      setState(() {
        _estimating = false;
        _estimateError = 'Unable to estimate candidates';
        _estimated = null;
      });
    }
  }

  Map<String, dynamic> _draft() {
    final max = num.parse(_salaryCtrl.text.trim());
    final minParsed = num.tryParse(_salaryMinCtrl.text.trim());
    final min =
        (minParsed != null && minParsed > 0 && minParsed < max) ? minParsed : null;
    return {
      'jobType': _resolvedJobType,
      if (widget.businessId != null) 'businessId': widget.businessId,
      'skills': _skills.toList(),
      'location': [
        if (_locationLabel != null && _locationLabel!.isNotEmpty) _locationLabel!,
        if (_locationCtrl.text.trim().isNotEmpty) _locationCtrl.text.trim(),
      ].join(' · '),
      'workMode': _workMode,
      'salaryOffered': max,
      if (min != null) 'salaryMin': min,
      'salaryMax': max,
      'salaryNegotiable': _salaryNegotiable,
      if (_employmentType != null) 'employmentType': _employmentType,
      'experienceMinYears': int.tryParse(_expCtrl.text.trim()) ?? 0,
      'vacancies': _vacancies,
      'salaryPeriod': _salaryPeriod,
      if (_sectorId != null) 'sectorId': _sectorId,
      if (_positionId != null) 'positionId': _positionId,
      if (_specializationIds.isNotEmpty) 'specializationIds': _specializationIds,
      if (_skillIds.isNotEmpty) 'skillIds': _skillIds,
      if (_qualificationId != null) 'qualificationId': _qualificationId,
      'qualificationRequired': _qualificationRequired,
      if (_locationId != null) 'locationId': _locationId,
      if (_locationCtrl.text.trim().isNotEmpty) 'addressText': _locationCtrl.text.trim(),
      if (_descriptionCtrl.text.trim().isNotEmpty)
        'description': _descriptionCtrl.text.trim(),
    };
  }

  Future<void> _submit() async {
    if (_resolvedJobType.isEmpty) {
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

  Future<void> _onPaid(PaymentSuccessResponse payment) async {
    if (!mounted) return;
    try {
      if (payment.orderId == null || payment.paymentId == null) throw StateError('Missing payment reference');
      await ref.read(matchingRepositoryProvider).verifyPayment(payment.orderId!, payment.paymentId!);
      if (mounted) showGxSnack(context, 'Payment confirmed — matching started', type: GxSnackType.success);
    } catch (_) {
      if (mounted) showGxSnack(context, 'Payment confirmation is pending. Open Pending payments to check it.');
    }
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HiringRequestsScreen(businessId: widget.businessId)));
  }

  void _onPayFail(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _submitting = false);
    showGxSnack(context, 'Payment failed: ${r.message ?? 'try again'}',
        type: GxSnackType.error);
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _employmentType != null && _sectorId != null;
      case 1:
        return _positionId != null;
      case 2:
        return true;
      case 3:
        final salary = num.tryParse(_salaryCtrl.text.trim());
        return salary != null && salary > 0 && _locationId != null;
      case 4:
        return true;
      default:
        return false;
    }
  }

  void _onContinue() {
    if (_step < 4) {
      setState(() => _step++);
      if (_step == 3) _scheduleEstimate();
      return;
    }
    _submit();
  }

  void _onBack() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(hiringCatalogProvider).value ?? HiringCatalog.fallback;
    final creditApplied =
        (_fee != null) ? (_creditBalance.clamp(0, _fee!)) : 0;
    final due =
        (_fee != null) ? (_fee! - creditApplied).clamp(0, _fee!) : null;

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              _progress(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: switch (_step) {
                    0 => _stepSector(),
                    1 => _stepPosition(),
                    2 => _hj2Details(),
                    3 => _hj3Compensation(due, creditApplied),
                    _ => _hj4Preview(due, creditApplied, catalog),
                  },
                ),
              ),
              _footer(due),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 4),
      child: Row(
        children: [
          Semantics(
            label: 'Go back',
            button: true,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: context.gx.ink),
              onPressed: _onBack,
            ),
          ),
          Expanded(
            child: Text(
              'Hire Employee',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: context.gx.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HiringRequestsScreen()),
            ),
            child: const Text('My requests'),
          ),
          Text(
            '${_step + 1}/5',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.gx.ink.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                Expanded(
                  child: Semantics(
                    label: 'Step ${i + 1}: ${_stepLabels[i]}',
                    selected: i == _step,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? context.gx.accent
                            : context.gx.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                if (i < 3) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _stepLabels[_step],
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: context.gx.ink.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: context.gx.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: context.gx.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: selected
              ? context.gx.onAccent
              : context.gx.ink.withValues(alpha: 0.75),
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: context.gx.accent,
      backgroundColor: context.gx.card2,
      side: BorderSide(
        color: selected ? context.gx.accent : context.gx.border,
      ),
    );
  }

  // ── hj1: employment type + category catalog ─────────────────────────────
  Widget _stepSector() {
    final catalogue = ref.watch(_catalogueProvider);
    return catalogue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Unable to load sectors. $error'),
      data: (data) {
        final sectors = (data['sectors'] as List?) ?? [];
        final types = (data['employmentTypes'] as List?) ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Employment type', 'Full time, part time, intern, contract, or gig.'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in types)
                  _chip('${type['label']}', _employmentType == type['code'], () {
                    setState(() => _employmentType = '${type['code']}');
                  }),
              ],
            ),
            _sectionTitle('Sector', 'Changing sector clears the position and skills.'),
            if (sectors.isEmpty) const Text('No sectors yet. Import the hiring catalogue from admin.'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sector in sectors)
                  _chip('${sector['label']}', _sectorId == sector['id'], () {
                    setState(() {
                      _sectorId = '${sector['id']}';
                      _positionId = null;
                      _positionLabel = null;
                      _specializationIds.clear();
                      _skillIds.clear();
                      _skills.clear();
                      _jobTypeCtrl.clear();
                    });
                  }),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _stepPosition() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Position', 'Search the shared catalogue. The same id is used for candidates.'),
        if (_positionLabel != null) Text('Selected: $_positionLabel', style: const TextStyle(fontWeight: FontWeight.w800)),
        HiringPositionSearch(
          sectorId: _sectorId,
          selectedLabel: _positionLabel,
          onPick: (pick) async {
            setState(() {
              _positionId = pick.id;
              _positionLabel = pick.label;
              _jobTypeCtrl.text = pick.label;
              _specializationIds.clear();
              _skillIds.clear();
              _skills.clear();
              _specializationChoices = [];
              _skillChoices = [];
            });
            try {
              final detail = await ref.read(matchingRepositoryProvider).hiringPosition(pick.id);
              if (!mounted || _positionId != pick.id) return;
              setState(() {
                _typeLabel = '${detail['typeLabel'] ?? 'Type'}';
                _fieldPattern = '${detail['fieldPattern'] ?? 'typeChips'}';
                _specializationChoices = ((detail['specializations'] as List?) ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .where((row) => row['isActive'] != false)
                    .toList();
                _skillChoices = ((detail['skills'] as List?) ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .where((row) => row['isActive'] != false)
                    .toList();
              });
            } catch (_) {
              if (!mounted || _positionId != pick.id) return;
              setState(() => _estimateError = 'Unable to load position details');
            }
          },
        ),
      ],
    );
  }

  Widget _hj1Role(HiringCatalog catalog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'What role are you hiring for?',
          'Pick employment type and sector — candidates see this on Find a Job → Alerts.',
        ),
        Text(
          'EMPLOYMENT TYPE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: context.gx.ink.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in catalog.employmentTypes)
              _chip(t.label, _employmentType == t.code, () {
                setState(() => _employmentType = t.code);
                _scheduleEstimate();
              }),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'SECTOR / CATEGORY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: context.gx.ink.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in catalog.categories)
              _chip(c, _category == c, () {
                setState(() {
                  _category = c;
                  if (_jobTypeCtrl.text.trim().isEmpty) {
                    _jobTypeCtrl.text = c;
                  }
                });
                _scheduleEstimate();
              }),
          ],
        ),
        const SizedBox(height: 20),
        Semantics(
          label: 'Job title',
          textField: true,
          child: TextField(
            controller: _jobTypeCtrl,
            decoration: const InputDecoration(
              labelText: 'Job title',
              hintText: 'e.g. Cashier, Backend Engineer',
              helperText: 'Refine or override the category above',
            ),
          ),
        ),
      ],
    );
  }

  // ── hj2: skills, experience, description ────────────────────────────────
  Widget _hj2Details() {
    final catalogue = ref.watch(_catalogueProvider).value;
    final qualifications = ((catalogue?['qualifications'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final visibleSkills = _skillChoices.where((skill) {
      if (_showMoreSkills) return true;
      return skill['tier'] != 'more';
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(_typeLabel, 'Choices come from the selected position.'),
        if (_positionId == null) const Text('Select a position first.'),
        if (_specializationChoices.isEmpty && _positionId != null)
          const Text('This position has no specializations.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spec in _specializationChoices)
              _chip('${spec['label']}', _specializationIds.contains(spec['id']), () {
                final id = '${spec['id']}';
                setState(() {
                  if (_fieldPattern == 'specializationMulti') {
                    _specializationIds.contains(id)
                        ? _specializationIds.remove(id)
                        : _specializationIds.add(id);
                  } else {
                    _specializationIds
                      ..clear()
                      ..add(id);
                  }
                });
              }),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _qualificationId,
          decoration: const InputDecoration(labelText: 'Qualification (optional)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No qualification')),
            for (final qual in qualifications)
              DropdownMenuItem(value: '${qual['id']}', child: Text('${qual['label']}')),
          ],
          onChanged: (value) => setState(() => _qualificationId = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Qualification is required'),
          value: _qualificationRequired,
          onChanged: _qualificationId == null
              ? null
              : (value) => setState(() => _qualificationRequired = value),
        ),
        TextField(
          controller: _expCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Minimum experience (years)'),
          onChanged: (_) => _scheduleEstimate(),
        ),
        const SizedBox(height: 12),
        Text('Skills', style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink)),
        const SizedBox(height: 8),
        if (_skillChoices.isEmpty) const Text('This position has no catalogue skills.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final skill in visibleSkills)
              _chip('${skill['label']}', _skillIds.contains(skill['id']), () {
                final id = '${skill['id']}';
                final label = '${skill['label']}';
                setState(() {
                  if (_skillIds.contains(id)) {
                    _skillIds.remove(id);
                    _skills.remove(label);
                  } else {
                    _skillIds.add(id);
                    _skills.add(label);
                  }
                });
                _scheduleEstimate();
              }),
          ],
        ),
        if (_skillChoices.any((skill) => skill['tier'] == 'more'))
          TextButton(
            onPressed: () => setState(() => _showMoreSkills = !_showMoreSkills),
            child: Text(_showMoreSkills ? 'Fewer skills' : 'More skills'),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Job description (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  // ── hj3: location, salary, vacancies, live estimate ─────────────────────
  Widget _hj3Compensation(int? due, int creditApplied) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Location & compensation',
          'Salary drives matching — live candidate count updates as you type.',
        ),
        HiringLocationSearch(
          selectedLabel: _locationLabel,
          onPick: (pick) {
            setState(() {
              _locationId = pick.id;
              _locationLabel = pick.label;
            });
            _scheduleEstimate();
          },
        ),
        if (_locationLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_locationLabel!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _locationCtrl,
          decoration: const InputDecoration(
            labelText: 'Street address (optional)',
            hintText: 'Building, area, landmark',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in ['ONSITE', 'HYBRID', 'REMOTE'])
              _chip(mode, _workMode == mode, () => setState(() => _workMode = mode)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final period in ['HOURLY', 'DAILY', 'WEEKLY', 'MONTHLY', 'PER_JOB'])
              _chip(period, _salaryPeriod == period, () {
                setState(() => _salaryPeriod = period);
                _scheduleEstimate();
              }),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Salary minimum per month optional',
          textField: true,
          child: TextField(
            controller: _salaryMinCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Salary min (₹/$_salaryPeriod, optional)',
              helperText: 'Leave blank for a single offered amount',
            ),
            onChanged: (_) => _scheduleEstimate(),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Salary maximum per $_salaryPeriod',
          textField: true,
          child: TextField(
            controller: _salaryCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Salary max (₹/$_salaryPeriod)',
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Salary negotiable',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.gx.ink,
            ),
          ),
          subtitle: Text(
            'Widens matcher overlap for candidates below your minimum',
            style: TextStyle(
              fontSize: 12,
              color: context.gx.ink.withValues(alpha: 0.5),
            ),
          ),
          value: _salaryNegotiable,
          activeThumbColor: context.gx.onAccent,
          activeTrackColor: context.gx.accent,
          onChanged: (v) {
            setState(() => _salaryNegotiable = v);
            _scheduleEstimate();
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Vacancies: $_vacancies',
          style: TextStyle(fontWeight: FontWeight.w700, color: context.gx.ink),
        ),
        Semantics(
          label: 'Number of vacancies',
          slider: true,
          child: Slider(
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
        ),
        if (_creditBalance > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Hiring credit available: ₹$_creditBalance',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: GixbeeTheme.accentGreen,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _estimateCard(due, creditApplied),
      ],
    );
  }

  Widget _estimateCard(int? due, int creditApplied) {
    return Container(
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
                : _estimateError != null
                    ? _estimateError!
                    : _estimated == null
                    ? 'Enter position, location and salary for an estimate'
                    : _estimated == 0
                        ? 'No candidates match these requirements yet'
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
                  : 'Match fee: ₹$_fee (24 h guarantee). Fee follows vacancies, not a per-candidate package.',
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
    );
  }

  // ── hj4: candidate-facing preview card ──────────────────────────────────
  Widget _hj4Preview(int? due, int creditApplied, HiringCatalog catalog) {
    final salaryMax = _salaryCtrl.text.trim();
    final salaryMin = _salaryMinCtrl.text.trim();
    final location = [
      if (_locationLabel != null && _locationLabel!.isNotEmpty) _locationLabel!,
      if (_locationCtrl.text.trim().isNotEmpty) _locationCtrl.text.trim(),
    ].join(' · ');
    final exp = _expCtrl.text.trim();
    final minParsed = num.tryParse(salaryMin);
    final maxParsed = num.tryParse(salaryMax);
    final salaryLabel = () {
      if (maxParsed == null || maxParsed <= 0) return 'Salary TBD';
      if (minParsed != null && minParsed > 0 && minParsed < maxParsed) {
        return '₹$salaryMin–₹$salaryMax / ${_salaryPeriod.toLowerCase()}';
      }
      return '₹$salaryMax / ${_salaryPeriod.toLowerCase()}';
    }();
    final empLabel = catalog.labelForCode(_employmentType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Preview',
          'This is what interested candidates see before they tap Interested.',
        ),
        Semantics(
          label: 'Job preview card',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.gx.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.gx.border),
              boxShadow: [
                BoxShadow(
                  color: context.gx.ink.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.gx.accentSoft.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        empLabel.isNotEmpty ? empLabel : 'Full Time',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: context.gx.accent,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Smart Hiring',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _resolvedJobType,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: context.gx.ink,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: context.gx.ink.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.gx.ink.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  salaryLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: GixbeeTheme.accentGreen,
                  ),
                ),
                if (_salaryNegotiable)
                  Text(
                    'Negotiable',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.gx.ink.withValues(alpha: 0.55),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (exp.isNotEmpty && exp != '0')
                      _previewTag('$exp+ yrs exp'),
                    _previewTag('$_vacancies position${_vacancies > 1 ? 's' : ''}'),
                    for (final s in _skills.take(4)) _previewTag(s),
                    if (_skills.length > 4)
                      _previewTag('+${_skills.length - 4} more'),
                  ],
                ),
                if (_descriptionCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _descriptionCtrl.text.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: context.gx.ink.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Pay for Smart Matching — only interested candidates reach you. '
          '24 Hour Hiring Guarantee.',
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: context.gx.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 16),
        _estimateCard(due, creditApplied),
      ],
    );
  }

  Widget _previewTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.gx.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.gx.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: context.gx.ink.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _footer(int? due) {
    final isLast = _step == 4;
    String label;
    if (isLast) {
      if (_submitting) {
        label = 'Starting…';
      } else if (due == 0) {
        label = 'Start matching (use credit)';
      } else {
        label = 'Pay & start matching';
      }
    } else {
      label = 'Continue';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Semantics(
        label: label,
        button: true,
        enabled: _canContinue && !_submitting,
        child: GxButton(
          label: label,
          onTap: !_canContinue || _submitting ? null : _onContinue,
        ),
      ),
    );
  }
}
