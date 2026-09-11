import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'pending_payments_screen.dart';
import '../../repositories/events_repository.dart' show eventDate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/matching_repository.dart';
import 'hiring_catalog.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Candidate career profiles (FRD: first 2 free Job Types, +₹50/mo after).
/// These prefs power Hire Employee matching — without them, employers cannot
/// notify you on the Alerts tab.
class JobTypesScreen extends ConsumerStatefulWidget {
  /// Optional: after creating a profile, jump to Alerts for the loop hint.
  final VoidCallback? onCreatedHint;

  const JobTypesScreen({super.key, this.onCreatedHint});

  @override
  ConsumerState<JobTypesScreen> createState() => _JobTypesScreenState();
}

class _JobTypesScreenState extends ConsumerState<JobTypesScreen> {
  List<Map<String, dynamic>> _prefs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list =
          await ref.read(matchingRepositoryProvider).listPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load profiles: $e',
          type: GxSnackType.error);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final wasEmpty = _prefs.isEmpty;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JobTypeFormScreen(
          existing: existing,
          freeSlotsLeft: (2 - _prefs.length).clamp(0, 2),
        ),
      ),
    );
    if (changed == true) {
      await _load();
      if (wasEmpty &&
          _prefs.isNotEmpty &&
          widget.onCreatedHint != null &&
          mounted) {
        showGxSnack(
          context,
          'Profile saved — employers can match you via Hire Employee. Check Alerts for matches.',
          type: GxSnackType.success,
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> pref) async {
    final id = pref['id']?.toString();
    if (id == null) return;
    try {
      await ref.read(matchingRepositoryProvider).deletePreference(id);
      if (!mounted) return;
      showGxSnack(context, 'Job Type removed', type: GxSnackType.success);
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Could not delete', type: GxSnackType.error);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  int _daysUntilDeletable(Map<String, dynamic> pref) {
    final created = DateTime.tryParse(pref['createdAt']?.toString() ?? '');
    if (created == null) return 7;
    final unlock = created.add(const Duration(days: 7));
    final left = unlock.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left + (unlock.isAfter(DateTime.now()) ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(hiringCatalogProvider).value ?? HiringCatalog.fallback;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Profiles',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.gx.ink,
                    ),
                  ),
                ),
                Text(
                  '${_prefs.where((p) => p['isPaid'] != true).length}/2 free',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.gx.ink.withValues(alpha: 0.5),
                  ),
                ),
                IconButton(tooltip: 'Pending payments', icon: const Icon(Icons.receipt_long), onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()));
                  if (mounted) _load();
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Career profiles the Smart Hiring matcher uses when employers run Hire Employee. '
              'Profile name locks after save; delete only after 7 days. Extra profiles cost ₹50/month. '
              'Separate from classic board preferences on the Board tab.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.gx.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _prefs.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              GxEmptyState(
                                icon: Icons.badge_outlined,
                                title: 'No profiles yet',
                                message:
                                    'Add up to 2 free career profiles so employers using Hire Employee can match you. Alerts then appear on the Alerts tab.',
                                actionLabel: 'Add profile',
                                onAction: () => _openForm(),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _prefs.length,
                            itemBuilder: (_, i) {
                              final p = _prefs[i];
                              final days = _daysUntilDeletable(p);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: context.gx.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _openForm(existing: p),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${p['jobType'] ?? ''}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    color: context.gx.ink,
                                                  ),
                                                ),
                                              ),
                                              if (p['isPaid'] == true)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: GixbeeTheme
                                                        .accentGreen
                                                        .withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: const Text(
                                                    'PAID',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      color: GixbeeTheme
                                                          .accentGreen,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          if (p['isPaid'] == true) Text(
                                            '${DateTime.tryParse('${p['paidUntil']}')?.isAfter(DateTime.now()) == true ? 'Active until' : 'Matching paused · expired'} ${eventDate(p['paidUntil'])}. Tap to renew.'),
                                          Text(
                                            [
                                              if (p['employmentType'] != null)
                                                catalog.labelForCode(
                                                    p['employmentType']
                                                        ?.toString()),
                                              if ((p['preferredLocation'] ?? '')
                                                  .toString()
                                                  .isNotEmpty)
                                                '${p['preferredLocation']}',
                                              if (p['expectedSalary'] != null)
                                                '₹${p['expectedSalary']}/mo${p['salaryNegotiable'] == true ? ' negotiable' : ''}',
                                              '${p['experienceYears'] ?? 0} yrs',
                                              '${p['noticePeriod'] ?? 'IMMEDIATE'}',
                                            ].where((s) => s.isNotEmpty).join(' · '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.55),
                                            ),
                                          ),
                                          if ((p['skills'] as List?)
                                                  ?.isNotEmpty ==
                                              true) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                for (final s
                                                    in (p['skills'] as List)
                                                        .take(6))
                                                  Chip(
                                                    label: Text('$s'),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                days > 0
                                                    ? 'Delete in $days day${days == 1 ? '' : 's'}'
                                                    : 'Can delete',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.gx.ink
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                              const Spacer(),
                                              TextButton(
                                                onPressed: days > 0
                                                    ? null
                                                    : () => _delete(p),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: GxButton(
              label: _prefs.length >= 2
                  ? 'Add Job Type (₹50/mo)'
                  : 'Add Job Type',
              accent: GixbeeTheme.accentGreen,
              onTap: () => _openForm(),
            ),
          ),
        ],
      ),
    );
  }
}

class JobTypeFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  final int freeSlotsLeft;

  const JobTypeFormScreen({
    super.key,
    this.existing,
    this.freeSlotsLeft = 2,
  });

  @override
  ConsumerState<JobTypeFormScreen> createState() => _JobTypeFormScreenState();
}

class _JobTypeFormScreenState extends ConsumerState<JobTypeFormScreen> {
  final _jobTypeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _locationFocus = FocusNode();
  final _salaryCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _skillCtrl = TextEditingController();
  final Set<String> _skills = {};
  String? _employmentType;
  bool _salaryNegotiable = false;
  String _notice = 'IMMEDIATE';
  bool _saving = false;
  Razorpay? _razorpay;
  Map<String, dynamic>? _pendingPaidBody;

  bool get _isEdit => widget.existing != null;

  static const _noticeOptions = [
    'IMMEDIATE',
    'DAYS_15',
    'DAYS_30',
    'DAYS_60',
    'DAYS_90',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _jobTypeCtrl.text = '${e['jobType'] ?? ''}';
      _locationCtrl.text = '${e['preferredLocation'] ?? ''}';
      _salaryCtrl.text = e['expectedSalary'] != null
          ? '${e['expectedSalary']}'
          : '';
      _expCtrl.text = '${e['experienceYears'] ?? 0}';
      _notice = '${e['noticePeriod'] ?? 'IMMEDIATE'}';
      _employmentType = e['employmentType']?.toString();
      _salaryNegotiable = e['salaryNegotiable'] == true;
      _skills.addAll(
          (e['skills'] as List? ?? []).map((s) => s.toString()));
    }
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _jobTypeCtrl.dispose();
    _locationCtrl.dispose();
    _locationFocus.dispose();
    _salaryCtrl.dispose();
    _expCtrl.dispose();
    _skillCtrl.dispose();
    super.dispose();
  }

  Widget _preferredLocationField() {
    final citiesAsync = ref.watch(citiesProvider);
    final cities = citiesAsync.value ?? const <CityEntry>[];

    return RawAutocomplete<CityEntry>(
      textEditingController: _locationCtrl,
      focusNode: _locationFocus,
      displayStringForOption: (c) => c.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty || cities.isEmpty) {
          return const Iterable<CityEntry>.empty();
        }
        return cities.where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.state.toLowerCase().contains(q) ||
            c.displayName.toLowerCase().contains(q));
      },
      onSelected: (c) {
        _locationCtrl.text = c.name;
        _locationCtrl.selection =
            TextSelection.collapsed(offset: c.name.length);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Preferred location',
            hintText: citiesAsync.isLoading
                ? 'Loading cities…'
                : 'Search city from list',
            helperText: cities.isEmpty && !citiesAsync.isLoading
                ? 'City list unavailable — type a city name'
                : null,
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: context.gx.card,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, minWidth: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, i) {
                  final c = opts[i];
                  return ListTile(
                    dense: true,
                    title: Text(c.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink,
                        )),
                    subtitle: Text(c.state,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.gx.ink.withValues(alpha: 0.5),
                        )),
                    onTap: () => onSelected(c),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic> _body() => {
        'jobType': _jobTypeCtrl.text.trim(),
        'skills': _skills.toList(),
        'preferredLocation': _locationCtrl.text.trim(),
        if (int.tryParse(_salaryCtrl.text.trim()) != null)
          'expectedSalary': int.parse(_salaryCtrl.text.trim()),
        'salaryNegotiable': _salaryNegotiable,
        if (_employmentType != null) 'employmentType': _employmentType,
        if (int.tryParse(_expCtrl.text.trim()) != null)
          'experienceYears': int.parse(_expCtrl.text.trim()),
        'noticePeriod': _notice,
      };

  Future<void> _save() async {
    if (_jobTypeCtrl.text.trim().isEmpty) {
      showGxSnack(context, 'Job Type is required', type: GxSnackType.error);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(matchingRepositoryProvider);
    try {
      if (_isEdit) {
        final id = widget.existing!['id'].toString();
        final body = _body()..remove('jobType'); // immutable
        await repo.updatePreference(id, body);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final result = await repo.createPreference(_body());
      if (result['needsPayment'] == true) {
        await _payExtraJobType(_body());
        return;
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Save failed', type: GxSnackType.error);
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
      setState(() => _saving = false);
    }
  }

  Future<void> _payExtraJobType(Map<String, dynamic> body) async {
    try {
      final order = await ref
          .read(matchingRepositoryProvider)
          .createExtraJobTypeOrder(body);
      _pendingPaidBody = body;
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
        'description': 'Extra Job Type — ₹50/month',
        'timeout': AppConfig.paymentTimeoutSeconds,
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
      });
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      final m = (msg ?? '').toLowerCase();
      showGxSnack(
        context,
        m.contains('not configured') || m.contains('not available')
            ? 'Payment gateway is not configured yet — your first 2 Job Types stay free without Razorpay.'
            : (msg ?? 'Payment unavailable'),
        type: GxSnackType.error,
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _onPaid(PaymentSuccessResponse payment) async {
    if (!mounted) return;
    try {
      if (payment.orderId == null || payment.paymentId == null) throw StateError('Missing payment reference');
      await ref.read(matchingRepositoryProvider).verifyPayment(payment.orderId!, payment.paymentId!);
      if (mounted) showGxSnack(context, 'Payment confirmed — profile access updated', type: GxSnackType.success);
    } catch (_) {
      if (mounted) showGxSnack(context, 'Payment confirmation is pending. Open Pending payments to check it.');
    }
    if (mounted) Navigator.pop(context, true);
  }

  void _onPayFail(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _saving = false);
    showGxSnack(context, 'Payment failed: ${r.message ?? 'try again'}',
        type: GxSnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(hiringCatalogProvider).value ?? HiringCatalog.fallback;
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit profile' : 'New profile'),
      ),
      body: DribbbleBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            if (_isEdit && widget.existing!['isPaid'] == true) ...[
              Text('Matching access until ${eventDate(widget.existing!['paidUntil'])}'),
              const SizedBox(height: 8),
              GxButton(label: 'Renew access · ₹50 / 30 days', loading: _saving, filled: false, onTap: () async {
                if (_saving) return;
                setState(() => _saving = true);
                await _payExtraJobType({..._body(), 'renewPreferenceId': widget.existing!['id']});
              }),
              const SizedBox(height: 20),
            ],
            if (!_isEdit) ...[
              Text(
                'CATEGORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: context.gx.ink.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in catalog.categories)
                    ChoiceChip(
                      label: Text(c,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _jobTypeCtrl.text == c
                                ? context.gx.onAccent
                                : context.gx.ink.withValues(alpha: 0.75),
                          )),
                      selected: _jobTypeCtrl.text == c,
                      onSelected: (_) => setState(() => _jobTypeCtrl.text = c),
                      selectedColor: context.gx.accent,
                      backgroundColor: context.gx.card2,
                      side: BorderSide(
                        color: _jobTypeCtrl.text == c
                            ? context.gx.accent
                            : context.gx.border,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _jobTypeCtrl,
              enabled: !_isEdit,
              decoration: InputDecoration(
                labelText: 'Profile name / job type',
                hintText: 'e.g. Cashier, Backend Engineer',
                helperText: _isEdit
                    ? 'Profile name cannot be changed after creation'
                    : widget.freeSlotsLeft > 0
                        ? '${widget.freeSlotsLeft} free slot(s) left'
                        : 'This will cost ₹50/month',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'EMPLOYMENT TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.gx.ink.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in catalog.employmentTypes)
                  ChoiceChip(
                    label: Text(t.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _employmentType == t.code
                              ? context.gx.onAccent
                              : context.gx.ink.withValues(alpha: 0.75),
                        )),
                    selected: _employmentType == t.code,
                    onSelected: (_) =>
                        setState(() => _employmentType = t.code),
                    selectedColor: context.gx.accent,
                    backgroundColor: context.gx.card2,
                    side: BorderSide(
                      color: _employmentType == t.code
                          ? context.gx.accent
                          : context.gx.border,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _preferredLocationField(),
            const SizedBox(height: 12),
            TextField(
              controller: _salaryCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Expected salary (₹/month)',
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
                'Matcher can include offers below employer minimum',
                style: TextStyle(
                  fontSize: 12,
                  color: context.gx.ink.withValues(alpha: 0.5),
                ),
              ),
              value: _salaryNegotiable,
              activeThumbColor: context.gx.onAccent,
              activeTrackColor: context.gx.accent,
              onChanged: (v) => setState(() => _salaryNegotiable = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Experience (years)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _noticeOptions.contains(_notice) ? _notice : 'IMMEDIATE',
              decoration: const InputDecoration(labelText: 'Notice period'),
              items: [
                for (final n in _noticeOptions)
                  DropdownMenuItem(value: n, child: Text(n.replaceAll('_', ' '))),
              ],
              onChanged: (v) => setState(() => _notice = v ?? 'IMMEDIATE'),
            ),
            const SizedBox(height: 16),
            Text('Skills',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: context.gx.ink)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _skillCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Add a skill',
                    ),
                    onSubmitted: (_) {
                      final s = _skillCtrl.text.trim();
                      if (s.isEmpty) return;
                      setState(() {
                        _skills.add(s);
                        _skillCtrl.clear();
                      });
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
                    onDeleted: () => setState(() => _skills.remove(s)),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            GxButton(
              label: _saving ? 'Saving…' : 'Save',
              onTap: _saving ? null : _save,
            ),
            if (_pendingPaidBody != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Waiting for payment confirmation… ${DateFormat.Hm().format(DateTime.now())}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.45),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
