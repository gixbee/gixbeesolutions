import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../providers/hiring_catalogue_provider.dart';
import '../../repositories/matching_repository.dart';
import '../jobs/hiring_catalog.dart';
import '../jobs/hiring_master_picker.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'hiring_employment_cards.dart';
import 'hiring_language_picker.dart';
import 'hiring_location_pay.dart';
import 'hiring_requests_screen.dart';
import 'hiring_sector_grid.dart';
import 'hiring_wizard_chips.dart';

/// Employer Smart Hiring wizard: estimate → pay → match.
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
  bool _skillSheetShowAll = false;
  String? _locationId;
  String? _locationLabel;
  final List<String> _specializationIds = [];
  final List<String> _skillIds = [];
  bool _qualificationRequired = false;
  String? _category;
  final _jobTypeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _salaryMinCtrl = TextEditingController(text: '25000');
  final _salaryCtrl = TextEditingController();
  final _expCtrl = TextEditingController(text: '0');
  final _descriptionCtrl = TextEditingController();
  final Set<String> _skills = {};
  int _vacancies = 1;
  bool _salaryNegotiable = false;
  final List<String> _languageIds = ['en', 'ml'];
  int _experienceYears = 0;
  int _positionDetailGen = 0;
  int _estimateGen = 0;

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
      final available = c['availableHiringCoins'] ?? c['balance'];
      setState(() => _creditBalance = num.tryParse('$available')?.toInt() ?? 0);
    } catch (_) {}
  }

  void _scheduleEstimate() {
    _debounce?.cancel();
    _estimateGen++;
    setState(() {
      _estimated = null;
      _estimateError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 400), _estimate);
  }

  Future<void> _estimate() async {
    final jobType = _resolvedJobType;
    final pay = _salaryRange;
    final gen = ++_estimateGen;
    if (jobType.isEmpty || pay == null || _locationId == null) {
      setState(() {
        _estimated = null;
        _fee = null;
        _estimating = false;
      });
      return;
    }
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final est = await repo.estimate(
        jobType: jobType,
        salary: pay.max,
        salaryMin: pay.min,
        salaryMax: pay.max,
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
        languageIds: _languageIds,
      );
      if (!mounted || gen != _estimateGen) return;
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
      if (!mounted || gen != _estimateGen) return;
      setState(() {
        _estimated = (est['estimated'] as num?)?.toInt() ?? 0;
        _fee = fee;
        _estimating = false;
      });
    } catch (_) {
      if (!mounted || gen != _estimateGen) return;
      setState(() {
        _estimating = false;
        _estimateError = 'Unable to estimate candidates';
        _estimated = null;
      });
    }
  }

  String? _salaryIssue() {
    bool valid(num? value) => value != null && value.isFinite &&
        value >= 0.01 && value <= 99999999;
    final min = num.tryParse(_salaryMinCtrl.text.trim());
    if (!valid(min)) return 'Enter a valid minimum salary';
    final maxText = _salaryCtrl.text.trim();
    if (maxText.isEmpty) return null;
    final max = num.tryParse(maxText);
    if (!valid(max)) return 'Enter a valid maximum salary';
    if (max! < min!) return 'Maximum salary cannot be below the minimum';
    return null;
  }

  ({num min, num max})? get _salaryRange {
    if (_salaryIssue() != null) return null;
    final min = num.parse(_salaryMinCtrl.text.trim());
    return (min: min, max: num.tryParse(_salaryCtrl.text.trim()) ?? min);
  }

  Map<String, dynamic> _draft() {
    final pay = _salaryRange!;
    return {
      'jobType': _resolvedJobType,
      if (widget.businessId != null) 'businessId': widget.businessId,
      'skills': _skills.toList(),
      'location': [
        if (_locationLabel != null && _locationLabel!.isNotEmpty) _locationLabel!,
        if (_locationCtrl.text.trim().isNotEmpty) _locationCtrl.text.trim(),
      ].join(' · '),
      'workMode': _workMode,
      'salaryOffered': pay.max,
      'salaryMin': pay.min,
      'salaryMax': pay.max,
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
      if (_languageIds.isNotEmpty) 'languageIds': _languageIds,
    };
  }

  Future<void> _submit() async {
    if (_resolvedJobType.isEmpty) {
      showGxSnack(context, 'Job Type is required', type: GxSnackType.error);
      return;
    }
    final salaryIssue = _salaryIssue();
    if (salaryIssue != null) {
      showGxSnack(context, salaryIssue, type: GxSnackType.error);
      return;
    }
    setState(() => _submitting = true);
    final repo = ref.read(matchingRepositoryProvider);
    try {
      final draft = _draft();
      final result = await repo.createRequest(draft);
      if (result['needsPayment'] == true) {
        await _payAndCreate(draft);
        return;
      }
      if (!mounted) return;
      showGxSnack(context, 'Matching started',
          type: GxSnackType.success);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HiringRequestsScreen(businessId: widget.businessId),
        ),
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
        'description': 'Smart Hiring match fee (₹${order['amountDue'] ?? ''})',
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
        if (_languageIds.isEmpty) return false;
        if (_specializationChoices.isNotEmpty && _specializationIds.isEmpty) {
          return false;
        }
        return true;
      case 3:
        if (_locationId == null || _salaryIssue() != null) return false;
        return true;
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
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _progress(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  _step >= 2 ? 96 : 20,
                ),
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
              MaterialPageRoute(
                builder: (_) => HiringRequestsScreen(businessId: widget.businessId),
              ),
            ),
            child: const Text('My requests'),
          ),
          Text(
            '${_step + 1}/5',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.gxMutedInk,
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
                if (i < 4) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _stepLabels[_step].toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: context.gxMutedInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldCaption(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.gx.ink.withValues(alpha: 0.75),
        ),
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
            color: context.gxMutedInk,
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return HiringWizardChip(label: label, selected: selected, onTap: onTap);
  }

  // ── hj1: employment type + category catalog ─────────────────────────────
  Widget _stepSector() {
    final catalogue = ref.watch(hiringCatalogueSnapshotProvider);
    return catalogue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Unable to load sectors. $error'),
      data: (data) {
        final sectors = ((data['sectors'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((s) => s['isActive'] != false)
            .toList();
        final types = ((data['employmentTypes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              'What type of help do you need?',
              'Choose how you want to hire.',
            ),
            HiringEmploymentCards(
              types: types,
              selectedCode: _employmentType,
              onSelect: (code) => setState(() => _employmentType = code),
            ),
            const SizedBox(height: 28),
            _sectionTitle(
              'Select a sector',
              'Choose the type of work you need help with.',
            ),
            if (sectors.isEmpty)
              Text(
                'No sectors yet. Import the hiring catalogue from admin.',
                style: TextStyle(color: context.gxMutedInk),
              )
            else
              HiringSectorGrid(
                sectors: sectors,
                selectedId: _sectorId,
                onSelect: (sector) {
                  setState(() {
                    _sectorId = '${sector['id']}';
                    _positionId = null;
                    _positionLabel = null;
                    _specializationIds.clear();
                    _skillIds.clear();
                    _skills.clear();
                    _specializationChoices = [];
                    _skillChoices = [];
                    _jobTypeCtrl.clear();
                  });
                },
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
        HiringPositionSearch(
          sectorId: _sectorId,
          selectedId: _positionId,
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
            final detailGen = ++_positionDetailGen;
            try {
              final detail = await ref.read(matchingRepositoryProvider).hiringPosition(pick.id);
              if (!mounted || _positionId != pick.id || detailGen != _positionDetailGen) return;
              final specs = ((detail['specializations'] as List?) ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .where((row) => row['isActive'] != false)
                  .toList();
              setState(() {
                _typeLabel = '${detail['typeLabel'] ?? 'Type'}';
                _fieldPattern = '${detail['fieldPattern'] ?? 'typeChips'}';
                _specializationChoices = specs;
                _skillChoices = ((detail['skills'] as List?) ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .where((row) => row['isActive'] != false)
                    .toList();
                if (specs.isNotEmpty && _specializationIds.isEmpty) {
                  _specializationIds.add('${specs.first['id']}');
                }
              });
            } catch (_) {
              if (!mounted || _positionId != pick.id || detailGen != _positionDetailGen) return;
              setState(() {
                _specializationChoices = [];
                _skillChoices = [];
              });
              showGxSnack(context, 'Unable to load position details', type: GxSnackType.error);
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
            color: context.gxMutedInk,
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
            color: context.gxMutedInk,
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
    final catalogue = ref.watch(hiringCatalogueSnapshotProvider).value;
    final qualifications = ((catalogue?['qualifications'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(_typeLabel, 'Choices come from the selected position.'),
        if (_positionId == null) const Text('Select a position first.'),
        if (_positionDetailGen > 0 &&
            _specializationChoices.isEmpty &&
            _positionId != null &&
            _skillChoices.isEmpty)
          const Text('Loading position details…'),
        if (_specializationChoices.isNotEmpty) ...[
          Text(
            '${_typeLabel}${_specializationIds.isNotEmpty ? ' (${_specializationIds.length} selected)' : ''}',
            style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final spec in _specializationChoices.take(6))
                _chip('${spec['label']}', _specializationIds.contains(spec['id']), () {
                  final id = '${spec['id']}';
                  setState(() {
                    if (_specializationIds.contains(id)) {
                      if (_specializationIds.length <= 1) return;
                      _specializationIds.remove(id);
                    } else {
                      _specializationIds.add(id);
                    }
                  });
                  _scheduleEstimate();
                }),
              for (final spec in _specializationChoices.skip(6))
                if (_specializationIds.contains('${spec['id']}'))
                  InputChip(
                    label: Text('${spec['label']}'),
                    onDeleted: () {
                      setState(() => _specializationIds.remove('${spec['id']}'));
                      _scheduleEstimate();
                    },
                  ),
            ],
          ),
          if (_specializationChoices.length > 6)
            TextButton(onPressed: _openSpecializationSheet, child: const Text('Show more')),
        ],
        const SizedBox(height: 16),
        _fieldCaption('Qualification (optional)'),
        DropdownButtonFormField<String>(
          value: _qualificationId,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('No qualification')),
            for (final qual in qualifications)
              DropdownMenuItem(value: '${qual['id']}', child: Text('${qual['label']}')),
          ],
          onChanged: (value) => setState(() {
            _qualificationId = value;
            if (value == null) _qualificationRequired = false;
          }),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Qualification is required',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _qualificationId == null
                        ? context.gxMutedInk
                        : context.gx.ink,
                  ),
                ),
              ),
              Switch(
                value: _qualificationRequired,
                onChanged: _qualificationId == null
                    ? null
                    : (value) => setState(() => _qualificationRequired = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Minimum experience (years)', style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink)),
            const Spacer(),
            IconButton(
              onPressed: _experienceYears > 0
                  ? () {
                      setState(() => _experienceYears -= 1);
                      _expCtrl.text = '$_experienceYears';
                      _scheduleEstimate();
                    }
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_experienceYears', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            IconButton(
              onPressed: () {
                setState(() => _experienceYears += 1);
                _expCtrl.text = '$_experienceYears';
                _scheduleEstimate();
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Skills (${_skillIds.length} selected)',
          style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
        ),
        const SizedBox(height: 8),
        if (_skillChoices.isEmpty && _positionId != null)
          const Text('This position has no catalogue skills yet.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in _skillIds)
              InputChip(
                label: Text(_skillLabel(id)),
                onDeleted: () {
                  setState(() {
                    _skillIds.remove(id);
                    _skills.remove(_skillLabel(id));
                  });
                  _scheduleEstimate();
                },
              ),
          ],
        ),
        HiringAddButton(
          label: 'Add skills',
          onPressed: _skillChoices.isEmpty ? null : _openSkillsSheet,
        ),
        const SizedBox(height: 8),
        HiringLanguageSection(
          selectedIds: _languageIds,
          applyEmployerDefaults: true,
          minSelection: 1,
          catalogRows: ((catalogue?['languages'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
          onChanged: (ids) {
            setState(() {
              _languageIds
                ..clear()
                ..addAll(ids);
            });
            _scheduleEstimate();
          },
        ),
        const SizedBox(height: 12),
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

  String _skillLabel(String id) {
    for (final skill in _skillChoices) {
      if ('${skill['id']}' == id) return '${skill['label']}';
    }
    return id;
  }

  String _specLabel(String id) {
    for (final spec in _specializationChoices) {
      if ('${spec['id']}' == id) return '${spec['label']}';
    }
    return id;
  }

  Future<void> _openSkillsSheet() async {
    final draftIds = {..._skillIds};
    final qCtrl = TextEditingController();
    var showAll = _skillSheetShowAll;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = qCtrl.text.trim().toLowerCase();
            var list = _skillChoices.where((skill) {
              if (q.isNotEmpty) {
                return '${skill['label']}'.toLowerCase().contains(q);
              }
              if (showAll) return true;
              return skill['tier'] != 'more';
            }).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Add skills (${draftIds.length} selected)',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: qCtrl,
                        decoration: const InputDecoration(hintText: 'Search skills'),
                        onChanged: (_) => setSheet(() {}),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final skill in list)
                            CheckboxListTile(
                              value: draftIds.contains('${skill['id']}'),
                              title: Text('${skill['label']}'),
                              subtitle: skill['tier'] == 'more' ? const Text('Additional skill') : null,
                              onChanged: (v) {
                                setSheet(() {
                                  final id = '${skill['id']}';
                                  if (v == true) {
                                    draftIds.add(id);
                                  } else {
                                    draftIds.remove(id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    if (_skillChoices.any((s) => s['tier'] == 'more') && q.isEmpty)
                      TextButton(
                        onPressed: () => setSheet(() => showAll = !showAll),
                        child: Text(showAll ? 'Fewer skills' : 'Show more skills'),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _skillIds
                                ..clear()
                                ..addAll(draftIds);
                              _skills
                                ..clear()
                                ..addAll(_skillIds.map(_skillLabel));
                              _skillSheetShowAll = showAll;
                            });
                            _scheduleEstimate();
                            Navigator.pop(ctx);
                          },
                          child: Text('OK (${draftIds.length} selected)'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    qCtrl.dispose();
  }

  Future<void> _openSpecializationSheet() async {
    final draft = {..._specializationIds};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${_typeLabel} (${draft.length} selected)',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final spec in _specializationChoices)
                          CheckboxListTile(
                            value: draft.contains('${spec['id']}'),
                            title: Text('${spec['label']}'),
                            onChanged: (v) {
                              setSheet(() {
                                final id = '${spec['id']}';
                                if (v == true) {
                                  draft.add(id);
                                } else if (draft.length > 1) {
                                  draft.remove(id);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _specializationIds
                            ..clear()
                            ..addAll(draft);
                        });
                        _scheduleEstimate();
                        Navigator.pop(ctx);
                      },
                      child: Text('OK (${draft.length} selected)'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── step 4/5: location, pay, live estimate ───────────────────────────────
  Widget _hj3Compensation(int? due, int creditApplied) {
    final catalogue = ref.watch(hiringCatalogueSnapshotProvider);
    final salaryUnit = hiringSalaryUnitLabel(_salaryPeriod);
    final salaryRangeError = _salaryIssue();

    return catalogue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Unable to load pay options. $e'),
      data: (data) {
        final periods = ((data['salaryPeriods'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              'Where do you need help?',
              'Set the work location and salary to help us find matching candidates.',
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.gx.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.gx.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: context.gxAccentInk, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Job location',
                        style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  HiringLocationSearch(
                    embedded: true,
                    enableGps: !kIsWeb,
                    selectedLabel: _locationLabel,
                    selectedId: _locationId,
                    onSelectionCleared: () {
                      setState(() {
                        _locationId = null;
                        _locationLabel = null;
                      });
                      _scheduleEstimate();
                    },
                    onPick: (pick) {
                      setState(() {
                        _locationId = pick.id;
                        _locationLabel = pick.label;
                      });
                      _scheduleEstimate();
                    },
                  ),
                  if (_locationId == null && _locationLabel == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Choose a location from search results',
                        style: TextStyle(fontSize: 12, color: context.gxMutedInk),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _locationCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Street address (optional)',
                      prefixIcon: Icon(Icons.home_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      filled: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            HiringWorkModeCards(
              selected: _workMode,
              onSelect: (mode) {
                setState(() => _workMode = mode);
                _scheduleEstimate();
              },
            ),
            const SizedBox(height: 24),
            HiringSalaryPeriodChips(
              periods: periods.isNotEmpty
                  ? periods
                  : [
                      {'code': 'HOURLY', 'label': 'Hourly'},
                      {'code': 'DAILY', 'label': 'Daily'},
                      {'code': 'WEEKLY', 'label': 'Weekly'},
                      {'code': 'MONTHLY', 'label': 'Monthly'},
                      {'code': 'PER_JOB', 'label': 'Per job'},
                    ],
              selectedCode: _salaryPeriod,
              onSelect: (code) {
                setState(() => _salaryPeriod = code);
                _scheduleEstimate();
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Salary range',
              style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldCaption('Min (₹/$salaryUnit) · required'),
                      TextField(
                        controller: _salaryMinCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onChanged: (_) => _scheduleEstimate(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldCaption('Max (₹/$salaryUnit) · optional'),
                      TextField(
                        controller: _salaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onChanged: (_) => _scheduleEstimate(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (salaryRangeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  salaryRangeError,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            HiringMatchEstimateCard(
              estimating: _estimating,
              error: _estimateError,
              estimated: _estimated,
              onRetry: _scheduleEstimate,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Salary negotiable',
                style: TextStyle(fontWeight: FontWeight.w600, color: context.gx.ink),
              ),
              subtitle: Text(
                'Widens matcher overlap for candidates below your minimum',
                style: TextStyle(fontSize: 12, color: context.gxMutedInk),
              ),
              value: _salaryNegotiable,
              activeThumbColor: context.gx.onAccent,
              activeTrackColor: Theme.of(context).colorScheme.primary,
              onChanged: (v) {
                setState(() => _salaryNegotiable = v);
                _scheduleEstimate();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Vacancies',
                  style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _vacancies > 1
                      ? () {
                          setState(() => _vacancies -= 1);
                          _scheduleEstimate();
                        }
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$_vacancies', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                IconButton(
                  onPressed: _vacancies < 25
                      ? () {
                          setState(() => _vacancies += 1);
                          _scheduleEstimate();
                        }
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_creditBalance > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Hiring Coins available: $_creditBalance',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.gxSuccessInk,
                ),
              ),
            ],
            if (_fee != null) ...[
              const SizedBox(height: 8),
              Text(
                creditApplied > 0
                    ? 'Match fee ₹$_fee · $creditApplied coins applied · pay ₹$due'
                    : 'Match fee: ₹$_fee (based on vacancies)',
                style: TextStyle(fontSize: 12, color: context.gxMutedInk),
              ),
            ],
          ],
        );
      },
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
                  ? 'Fee ₹$_fee · $creditApplied coins applied · pay ₹$due'
                  : 'Match fee: ₹$_fee (based on vacancies)',
              style: TextStyle(
                fontSize: 13,
                color: context.gx.ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── hj4: candidate-facing preview card ──────────────────────────────────
  Widget _hj4Preview(int? due, int creditApplied, HiringCatalog catalog) {
    final pay = _salaryRange;
    final location = [
      if (_locationLabel != null && _locationLabel!.isNotEmpty) _locationLabel!,
      if (_locationCtrl.text.trim().isNotEmpty) _locationCtrl.text.trim(),
    ].join(' · ');
    final exp = _expCtrl.text.trim();
    final unit = hiringSalaryUnitLabel(_salaryPeriod);
    final salaryLabel = pay == null
        ? 'Salary TBD'
        : pay.min == pay.max
            ? '₹${pay.min} / $unit'
            : '₹${pay.min}–₹${pay.max} / $unit';
    final empLabel = catalog.labelForCode(_employmentType);
    final catalogue = ref.watch(hiringCatalogueSnapshotProvider).value;
    final qualifications = ((catalogue?['qualifications'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final qualLabel = qualifications
        .where((q) => '${q['id']}' == _qualificationId)
        .map((q) => '${q['label']}')
        .firstOrNull;
    final sectorLabel = ((catalogue?['sectors'] as List?) ?? [])
        .cast<Map>()
        .where((s) => '${s['id']}' == _sectorId)
        .map((s) => '${s['label']}')
        .firstOrNull;
    final specText = _specializationIds.map(_specLabel).join(', ');
    final langText = _languageIds.map(HiringLanguageCatalog.labelFor).join(', ');
    final skillsText = _skills.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Review & publish', 'Confirm details and pay the Smart Hiring fee.'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.gx.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gx.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Job summary', style: TextStyle(fontWeight: FontWeight.w900, color: context.gx.ink)),
                  const Spacer(),
                  TextButton(onPressed: () => setState(() => _step = 2), child: const Text('Edit')),
                ],
              ),
              const SizedBox(height: 8),
              _summaryRow('Employment type', empLabel.isNotEmpty ? empLabel : '—'),
              _summaryRow('Sector', sectorLabel ?? '—'),
              _summaryRow('Position', _positionLabel ?? _resolvedJobType),
              if (specText.isNotEmpty) _summaryRow('Types / specializations', specText),
              if (qualLabel != null) _summaryRow('Qualification', qualLabel),
              _summaryRow('Experience', '${exp.isEmpty ? '0' : exp}+ years'),
              if (skillsText.isNotEmpty) _summaryRow('Skills', skillsText),
              if (langText.isNotEmpty) _summaryRow('Languages', langText),
              if (_descriptionCtrl.text.trim().isNotEmpty)
                _summaryRow('Description', _descriptionCtrl.text.trim()),
              _summaryRow('Work mode', hiringWorkModeLabel(_workMode)),
              if (location.isNotEmpty) _summaryRow('Location', location),
              _summaryRow('Salary', '$salaryLabel${_salaryNegotiable ? ' (negotiable)' : ''}'),
              _summaryRow('Vacancies', '$_vacancies'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle(
          'Candidate preview',
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
                          color: context.gxAccentInk,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Smart Hiring',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.gxMutedInk,
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
                        color: context.gxMutedInk,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.gxMutedInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  salaryLabel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: context.gxSuccessInk,
                  ),
                ),
                if (_salaryNegotiable)
                  Text(
                    'Negotiable',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.gxMutedInk,
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (exp.isNotEmpty && exp != '0') _previewTag('$exp+ yrs exp'),
                    _previewTag(hiringWorkModeLabel(_workMode)),
                    _previewTag('$_vacancies vacancy${_vacancies > 1 ? 'ies' : ''}'),
                    for (final s in _skills) _previewTag(s),
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
          'If zero candidates express interest within 24 hours, the full fee '
          'returns as Gixbee Hiring Coins. Each coin covers ₹1 of a future '
          'Hire Employee fee. Coins cannot be withdrawn or transferred.',
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: context.gxMutedInk,
          ),
        ),
        const SizedBox(height: 16),
        _estimateCard(due, creditApplied),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(fontSize: 13, color: context.gxMutedInk)),
          ),
          Expanded(
            flex: 3,
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.gx.ink)),
          ),
        ],
      ),
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
        label = 'Start matching (use coins)';
      } else {
        label = 'Pay & start matching';
      }
    } else {
      label = 'Continue';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_step == 3) ...[
            if (!_canContinue)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _locationId == null
                      ? 'Pick a job location from search results to continue.'
                      : 'Enter a valid salary to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.85),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'After publishing, matching candidates can express interest.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: context.gxMutedInk,
                ),
              ),
            ),
          ],
          Semantics(
            label: label,
            button: true,
            enabled: _canContinue && !_submitting,
            child: GxButton(
              label: label,
              icon: isLast ? null : Icons.arrow_forward,
              onTap: !_canContinue || _submitting ? null : _onContinue,
            ),
          ),
        ],
      ),
    );
  }
}
