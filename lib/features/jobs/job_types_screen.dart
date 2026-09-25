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
import '../../repositories/talent_repository.dart';
import 'hiring_catalog.dart';
import 'hiring_master_picker.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Candidate career profiles (FRD: first 2 free Job Types, +₹50/mo after).
/// These prefs power Hire Employee matching — without them, employers cannot
/// notify you on the Alerts tab.
class JobTypesScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCreatedHint;
  final VoidCallback? onCreateProfile;

  const JobTypesScreen({super.key, this.onCreatedHint, this.onCreateProfile});

  @override
  ConsumerState<JobTypesScreen> createState() => _JobTypesScreenState();
}

class _JobTypesScreenState extends ConsumerState<JobTypesScreen> {
  List<Map<String, dynamic>> _prefs = [];
  Map<String, dynamic>? _talent;
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
      Map<String, dynamic>? talent;
      try {
        talent = await ref.read(talentRepositoryProvider).getProfile();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _prefs = list;
        _talent = talent;
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
          existing: existing == null ? null : {
            ...existing,
            'availableOn': _talent?['availableOn'],
          },
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
          'Profile saved. Matching jobs are on the Jobs tab.',
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
      showGxSnack(context, 'Profile removed', type: GxSnackType.success);
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

  Future<void> _setOpenToWork(bool open) async {
    try {
      await ref.read(talentRepositoryProvider).updateProfile({
        'profileStatus': open ? 'ACTIVE' : 'PAUSED',
      });
      await _load();
      if (!mounted) return;
      showGxSnack(
        context,
        open
            ? 'You are open to work — all active profiles can match'
            : 'Open to work is off — no profiles will match until you turn it back on',
        type: GxSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Could not update profile: $e', type: GxSnackType.error);
    }
  }

  Future<void> _setPreferencePaused(Map<String, dynamic> pref, bool paused) async {
    final id = pref['id']?.toString();
    if (id == null) return;
    try {
      await ref.read(matchingRepositoryProvider).updatePreference(id, {
        'matchingPaused': paused,
      });
      await _load();
      if (!mounted) return;
      showGxSnack(
        context,
        paused
            ? '${pref['jobType']} paused — other profiles stay active'
            : '${pref['jobType']} is active for matching again',
        type: GxSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Could not update profile: $e', type: GxSnackType.error);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> pref) async {
    final days = _daysUntilDeletable(pref);
    if (days > 0) {
      showGxSnack(
        context,
        'Profiles can be deleted $days day${days == 1 ? '' : 's'} after creation (anti-spam rule).',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this profile?'),
        content: Text(
          'Remove "${pref['jobType']}" from your account? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _delete(pref);
  }

  int get _strength {
    final talent = _talent;
    if (talent == null) return 0;
    var filled = 0;
    const total = 8;
    if (_stringsOf(talent['preferredRoles']).isNotEmpty) filled++;
    if (_stringsOf(talent['employmentTypes']).isNotEmpty || _prefs.isNotEmpty) filled++;
    if (_stringsOf(talent['skills']).isNotEmpty) filled++;
    if ((talent['experience']?.toString() ?? '').isNotEmpty) filled++;
    if (talent['expectedSalary'] != null) filled++;
    if (talent['lat'] != null && talent['lng'] != null) filled++;
    if ((talent['travelRadiusKm'] as num?) != null) filled++;
    if ((talent['availability']?.toString() ?? '').isNotEmpty) filled++;
    return ((filled / total) * 100).round();
  }

  List<String> _stringsOf(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
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
                    'Job Profiles',
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
              'Create different profiles for different kinds of work.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.gx.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_talent != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Open to work'),
                subtitle: Text(
                  _talent?['profileStatus'] == 'PAUSED'
                      ? 'Off — employers cannot match any of your profiles'
                      : 'On — active profiles can receive matches and invites',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.55),
                  ),
                ),
                value: _talent?['profileStatus'] != 'PAUSED',
                activeThumbColor: GixbeeTheme.accentGreen,
                onChanged: _setOpenToWork,
              ),
            ),
          const SizedBox(height: 8),
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
                                title: 'No job profile yet',
                                message:
                                    'Create a profile so Gixbee can match you with suitable jobs.',
                                actionLabel: 'Create Profile',
                                onAction: widget.onCreateProfile ?? () => _openForm(),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _prefs.length,
                            itemBuilder: (_, i) {
                              final p = _prefs[i];
                              final days = _daysUntilDeletable(p);
                              final prefPaused = p['matchingPaused'] == true;
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
                                              if (prefPaused)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: context.gx.ink
                                                        .withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    'PAUSED',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      color: context.gx.ink
                                                          .withValues(alpha: 0.55),
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
                                            'Profile strength $_strength%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: GixbeeTheme.accentGreen,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              if (_stringsOf(_talent?['employmentTypes']).isNotEmpty)
                                                _stringsOf(_talent?['employmentTypes']).join(', ')
                                              else if (p['employmentType'] != null)
                                                catalog.labelForCode(p['employmentType']?.toString()),
                                              if ((_talent?['preferredLocations'] is List &&
                                                      (_talent!['preferredLocations'] as List).isNotEmpty)
                                                  || (p['preferredLocation'] ?? '').toString().isNotEmpty)
                                                (_talent?['preferredLocations'] is List &&
                                                        (_talent!['preferredLocations'] as List).isNotEmpty)
                                                    ? '${(_talent!['preferredLocations'] as List).first}'
                                                    : '${p['preferredLocation']}',
                                              if (p['expectedSalary'] != null)
                                                '₹${p['expectedSalary']} ${_talent?['expectedSalaryPeriod'] ?? 'MONTHLY'}${p['salaryNegotiable'] == true ? ' negotiable' : ''}',
                                              if (_talent?['travelRadiusKm'] != null)
                                                '${_talent!['travelRadiusKm']} km',
                                              '${_talent?['availability'] ?? p['noticePeriod'] ?? 'IMMEDIATE'}'
                                                  '${_talent?['availableOn'] != null ? ' · ${_talent!['availableOn']}' : ''}',
                                              '${p['experienceYears'] ?? 0} yrs',
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
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 0,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              TextButton(
                                                onPressed: () => _openForm(existing: p),
                                                child: const Text('Edit'),
                                              ),
                                              TextButton(
                                                onPressed: () => _setPreferencePaused(
                                                  p,
                                                  !prefPaused,
                                                ),
                                                child: Text(
                                                  prefPaused ? 'Resume' : 'Pause',
                                                ),
                                              ),
                                              TextButton.icon(
                                                onPressed: () => _confirmDelete(p),
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: days > 0
                                                      ? context.gx.ink.withValues(alpha: 0.35)
                                                      : Colors.red.shade700,
                                                ),
                                                label: Text(
                                                  days > 0 ? 'Delete ($days d)' : 'Delete',
                                                  style: TextStyle(
                                                    color: days > 0
                                                        ? context.gx.ink.withValues(alpha: 0.45)
                                                        : Colors.red.shade700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (days > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Delete unlocks $days day${days == 1 ? '' : 's'} after this profile was created.',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.gx.ink.withValues(alpha: 0.45),
                                                ),
                                              ),
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
              label: '+ Add another job profile',
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

  final String? initialJobType;
  final Map<String, dynamic>? initialPreference;

  const JobTypeFormScreen({
    super.key,
    this.existing,
    this.freeSlotsLeft = 2,
    this.initialJobType,
    this.initialPreference,
  });

  @override
  ConsumerState<JobTypeFormScreen> createState() => _JobTypeFormScreenState();
}

class _JobTypeFormScreenState extends ConsumerState<JobTypeFormScreen> {
  final _jobTypeCtrl = TextEditingController();
  String? _positionId;
  String? _sectorId;
  String? _qualificationId;
  String? _locationId;
  String? _locationLockedLabel;
  List<String> _specializationIds = [];
  List<String> _skillIds = [];
  final _locationCtrl = TextEditingController();
  final _locationFocus = FocusNode();
  final _salaryCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _skillCtrl = TextEditingController();
  final Set<String> _skills = {};
  String? _employmentType;
  bool _salaryNegotiable = false;
  String _notice = 'IMMEDIATE';
  String _salaryPeriod = 'MONTHLY';
  DateTime? _joinDate;
  bool _saving = false;
  Razorpay? _razorpay;
  Map<String, dynamic>? _pendingPaidBody;

  bool get _isEdit => widget.existing != null;

  static const _noticeOptions = [
    'IMMEDIATE',
    'DAYS_7',
    'DAYS_15',
    'DAYS_30',
    'DAYS_60',
    'DAYS_90',
    'CUSTOM_DATE',
  ];

  @override
  void initState() {
    super.initState();
    final seed = widget.initialPreference;
    if (widget.initialJobType != null && widget.initialJobType!.isNotEmpty) {
      _jobTypeCtrl.text = widget.initialJobType!;
    }
    if (seed != null) {
      final role = '${seed['jobType'] ?? ''}';
      if (role.isNotEmpty) _jobTypeCtrl.text = role;
      _locationCtrl.text = '${seed['preferredLocation'] ?? ''}';
      if (seed['expectedSalary'] != null) _salaryCtrl.text = '${seed['expectedSalary']}';
      _expCtrl.text = '${seed['experienceYears'] ?? 0}';
      _notice = '${seed['noticePeriod'] ?? 'IMMEDIATE'}';
      _joinDate = DateTime.tryParse('${seed['availableOn'] ?? ''}');
      _employmentType = seed['employmentType']?.toString();
      _salaryNegotiable = seed['salaryNegotiable'] == true;
      _salaryPeriod = '${seed['expectedSalaryPeriod'] ?? 'MONTHLY'}';
      _positionId = seed['positionId']?.toString();
      _sectorId = seed['sectorId']?.toString();
      _qualificationId = seed['qualificationId']?.toString();
      _locationId = seed['locationId']?.toString();
      _specializationIds = _idList(seed['specializationIds']);
      _skillIds = _idList(seed['skillIds']);
      final skills = seed['skills'];
      if (skills is List) {
        _skills.addAll(skills.map((skill) => skill.toString()).where((skill) => skill.isNotEmpty));
      }
    }
    final e = widget.existing;
    if (e != null) {
      _jobTypeCtrl.text = '${e['jobType'] ?? ''}';
      _locationCtrl.text = '${e['preferredLocation'] ?? ''}';
      _salaryCtrl.text = e['expectedSalary'] != null
          ? '${e['expectedSalary']}'
          : '';
      _expCtrl.text = '${e['experienceYears'] ?? 0}';
      _notice = '${e['noticePeriod'] ?? 'IMMEDIATE'}';
      _joinDate = DateTime.tryParse('${e['availableOn'] ?? ''}');
      _salaryPeriod = '${e['expectedSalaryPeriod'] ?? 'MONTHLY'}';
      _employmentType = e['employmentType']?.toString();
      _salaryNegotiable = e['salaryNegotiable'] == true;
      _positionId = e['positionId']?.toString();
      _sectorId = e['sectorId']?.toString();
      _qualificationId = e['qualificationId']?.toString();
      _locationId = e['locationId']?.toString();
      _specializationIds = _idList(e['specializationIds']);
      _skillIds = _idList(e['skillIds']);
      _skills.addAll(
          (e['skills'] as List? ?? []).map((s) => s.toString()));
    }
    if (_locationId != null) _locationLockedLabel = _locationCtrl.text;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HiringLocationSearch(
          selectedLabel: _locationId == null ? null : _locationCtrl.text,
          onPick: (pick) {
            setState(() {
              _locationId = pick.id;
              _locationLockedLabel = pick.label;
              _locationCtrl.text = pick.label;
            });
          },
        ),
        const SizedBox(height: 8),
        const Text('A serviceable-city shortcut clears the hiring location id.'),
        RawAutocomplete<CityEntry>(
      textEditingController: _locationCtrl,
      focusNode: _locationFocus,
      displayStringForOption: (c) => c.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty || cities.isEmpty) {
          return const Iterable<CityEntry>.empty();
        }
        return cities.where((c) => cityMatchesQuery(c, value.text));
      },
      onSelected: (c) {
        _locationCtrl.text = c.name;
        _locationCtrl.selection =
            TextSelection.collapsed(offset: c.name.length);
        setState(() {
          _locationId = null;
          _locationLockedLabel = null;
        });
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
          onChanged: (text) {
            if (_locationLockedLabel != null && text.trim() != _locationLockedLabel) {
              setState(() {
                _locationId = null;
                _locationLockedLabel = null;
              });
            }
          },
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
    ),
      ],
    );
  }

  List<String> _idList(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
    }
    if (value is String && value.isNotEmpty) {
      return value.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
    }
    return [];
  }

  Map<String, dynamic> _body() {
    final role = _jobTypeCtrl.text.trim();
    return {
      'jobType': role,
      'skills': _skills.toList(),
      'preferredLocation': _locationCtrl.text.trim(),
      if (int.tryParse(_salaryCtrl.text.trim()) != null)
        'expectedSalary': int.parse(_salaryCtrl.text.trim()),
      'salaryNegotiable': _salaryNegotiable,
      'expectedSalaryPeriod': _salaryPeriod,
      if (_employmentType != null) 'employmentType': _employmentType,
      if (int.tryParse(_expCtrl.text.trim()) != null)
        'experienceYears': int.parse(_expCtrl.text.trim()),
      'noticePeriod': _notice,
      'positionId': _positionId,
      'sectorId': _sectorId,
      'qualificationId': _qualificationId,
      'locationId': _locationId,
      'specializationIds': _specializationIds,
      'skillIds': _skillIds,
    };
  }

  Future<void> _save() async {
    if (_jobTypeCtrl.text.trim().isEmpty) {
      showGxSnack(context, 'Choose the kind of work', type: GxSnackType.error);
      return;
    }
    if (_notice == 'CUSTOM_DATE' && _joinDate == null) {
      showGxSnack(context, 'Choose the date you can join', type: GxSnackType.error);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(matchingRepositoryProvider);
    final body = _body();
    try {
      await ref.read(talentRepositoryProvider).updateProfile({
        'availability': _notice,
        'availableOn': _notice == 'CUSTOM_DATE' ? _dateOnly(_joinDate!) : null,
      });
      if (_isEdit) {
        final id = widget.existing!['id'].toString();
        final body = _body()..remove('jobType');
        await repo.updatePreference(id, body);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final result = await repo.createPreference(body);
      if (result['needsPayment'] == true) {
        await _payExtraJobType(body);
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
      if (!mounted) return;
      showGxSnack(context, 'Payment confirmed — profile access updated', type: GxSnackType.success);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      showGxSnack(context, 'Payment confirmation is pending. Open Pending payments to check it.');
      Navigator.pop(context, false);
    }
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
            if (_isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${widget.existing!['jobType'] ?? ''}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              )
            else if (widget.freeSlotsLeft <= 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Adding another profile costs ₹50/month.'),
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
                labelText: 'Expected pay (₹)',
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
                'Employers can still contact you if pay is flexible.',
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
              decoration: const InputDecoration(labelText: 'Available to Join'),
              items: [
                for (final n in _noticeOptions)
                  DropdownMenuItem(value: n, child: Text(_joinLabel(n))),
              ],
              onChanged: (v) async {
                final next = v ?? 'IMMEDIATE';
                if (next == 'CUSTOM_DATE') {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final lastDay = today.add(const Duration(days: 365 * 2));
                  final savedDate = _joinDate ?? today;
                  final initialDate = savedDate.isBefore(today)
                      ? today
                      : savedDate.isAfter(lastDay) ? lastDay : savedDate;
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: today,
                    lastDate: lastDay,
                    initialDate: initialDate,
                  );
                  if (picked == null) return;
                  setState(() {
                    _notice = next;
                    _joinDate = picked;
                  });
                  return;
                }
                setState(() {
                  _notice = next;
                  _joinDate = null;
                });
              },
            ),
            if (_notice == 'CUSTOM_DATE' && _joinDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Joining ${_dateOnly(_joinDate!)}'),
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

String _joinLabel(String code) => switch (code) {
      'IMMEDIATE' => 'Immediately',
      'DAYS_7' => 'Within 7 days',
      'DAYS_15' => 'Within 15 days',
      'DAYS_30' => 'Within 30 days',
      'DAYS_60' => 'Within 60 days',
      'DAYS_90' => 'Within 90 days',
      'CUSTOM_DATE' => 'Custom Date',
      _ => code,
    };

String _dateOnly(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
