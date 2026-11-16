import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/matching_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../business/hiring_language_picker.dart';
import '../business/hiring_sector_grid.dart';
import 'hiring_master_picker.dart';
import 'pending_payments_screen.dart';

bool jobProfileNeedsWizard(Map<String, dynamic> profile) {
  final lat = profile['lat'];
  final lng = profile['lng'];
  final location = _text(profile['locationId']);
  final hasPin = lat is num && lng is num && !(lat == 0 && lng == 0);
  return profile['profileStatus'] == 'INCOMPLETE' ||
      _strings(profile['preferredRoles']).isEmpty ||
      _strings(profile['employmentTypes']).isEmpty ||
      (location == null && !hasPin);
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _strings(Object? value) =>
    value is List ? value.map(_text).whereType<String>().toList() : [];

List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : [];

String _dateOnly(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

const _joinChoices = {
  'IMMEDIATE': 'Immediately',
  'DAYS_7': 'Within 7 days',
  'DAYS_15': 'Within 15 days',
  'DAYS_30': 'Within 30 days',
  'DAYS_60': 'Within 60 days',
  'DAYS_90': 'Within 90 days',
  'CUSTOM_DATE': 'Choose a date',
};

enum SeekerProfileResult { profiles, createAnother }

class SeekerProfileWizard extends ConsumerStatefulWidget {
  const SeekerProfileWizard({super.key, this.existing, this.freeSlotsLeft});
  final Map<String, dynamic>? existing;
  final int? freeSlotsLeft;

  @override
  ConsumerState<SeekerProfileWizard> createState() =>
      _SeekerProfileWizardState();
}

class _SeekerProfileWizardState extends ConsumerState<SeekerProfileWizard> {
  static const _steps = [
    'Job type & sector',
    'Position',
    'Your qualifications',
    'Location & pay expectations',
    'Review & save',
  ];
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _salary = TextEditingController();
  final _experience = TextEditingController(text: '0');
  final _search = TextEditingController();
  final _locations = <({String id, String label})>[];
  final _skillIds = <String>{};
  final _specializations = <String>{};
  List<String> _languages = [];
  List<String> _legacySkills = [];
  Map<String, dynamic>? _catalogue, _position;
  Object? _loadError, _positionError;
  int _step = 0, _positionLoad = 0, _locationPickerKey = 0;
  String? _sectorId, _positionId, _positionLabel, _employment, _qualification;
  String? _resumeId, _resumeName, _orderId;
  String _mode = 'ONSITE', _period = 'MONTHLY', _notice = 'IMMEDIATE';
  DateTime? _availableOn;
  bool _saving = false, _uploading = false, _positionLoading = false;
  bool _negotiable = false, _saved = false;
  Razorpay? _razorpay;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final saved = widget.existing;
    if (saved != null) {
      final details = saved['seekerDetails'] as Map? ?? {};
      _name.text = _text(details['profileName']) ?? '';
      _bio.text = _text(details['bio']) ?? '';
      _positionId = _text(saved['positionId']);
      _positionLabel = _text(saved['jobType']);
      _sectorId = _text(saved['sectorId']);
      _employment = _text(saved['employmentType']);
      _qualification = _text(saved['qualificationId']);
      final expected = num.tryParse('${saved['expectedSalary']}');
      if (expected != null && expected > 0) {
        _salary.text = expected == expected.roundToDouble()
            ? expected.toInt().toString()
            : expected.toString();
      }
      _experience.text = '${saved['experienceYears'] ?? 0}';
      _mode = _text(details['workMode']) ?? 'ONSITE';
      _period = _text(saved['expectedSalaryPeriod']) ?? 'MONTHLY';
      _notice = _text(saved['noticePeriod']) ?? 'IMMEDIATE';
      _availableOn = DateTime.tryParse(
          '${details['availableOn'] ?? saved['availableOn'] ?? ''}');
      _negotiable = saved['salaryNegotiable'] == true;
      _resumeId = _text(details['resumeId']);
      _resumeName = _text(details['resumeName']);
      _skillIds.addAll(_strings(saved['skillIds']));
      _specializations.addAll(_strings(saved['specializationIds']));
      _languages = _strings(saved['languageIds']);
      _legacySkills = _strings(saved['skills']);
      for (final row in _rows(details['locations'])) {
        final id = _text(row['id']), label = _text(row['label']);
        if (id != null && label != null) _locations.add((id: id, label: label));
      }
      if (_locations.isEmpty) {
        final id = _text(saved['locationId']);
        final label = _text(saved['preferredLocation']);
        if (id != null && label != null) _locations.add((id: id, label: label));
      }
    }
    _loadCatalogue();
  }

  @override
  void dispose() {
    for (final controller in [_name, _bio, _salary, _experience, _search]) {
      controller.dispose();
    }
    _razorpay?.clear();
    super.dispose();
  }

  Future<void> _loadCatalogue() async {
    setState(() => _loadError = null);
    try {
      final data = await ref.read(matchingRepositoryProvider).hiringCatalogue();
      if (!mounted) return;
      setState(() => _catalogue = data);
      if (_positionId != null) await _loadPosition(_positionId!);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Could not load the hiring catalogue.');
      }
    }
  }

  List<Map<String, dynamic>> _catalogueRows(String key) =>
      _rows(_catalogue?[key]);

  void _chooseSector(String id) {
    if (_sectorId == id) return;
    setState(() {
      _sectorId = id;
      _positionId = _positionLabel = null;
      _position = null;
      _positionLoad++;
      _positionLoading = false;
      _positionError = null;
      _specializations.clear();
      _skillIds.clear();
      _legacySkills = [];
      _search.clear();
    });
  }

  Future<void> _loadPosition(String id) async {
    final seq = ++_positionLoad;
    setState(() {
      _positionLoading = true;
      _positionError = null;
    });
    try {
      final item =
          await ref.read(matchingRepositoryProvider).hiringPosition(id);
      if (!mounted || seq != _positionLoad) return;
      setState(() {
        _position = item;
        _positionLabel = _text(item['label']) ?? _positionLabel;
        _positionLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _positionLoad) return;
      setState(() {
        _positionError = 'Could not load the position details.';
        _positionLoading = false;
      });
    }
  }

  String? _issue(int step) {
    if (step == 0 && (_employment == null || _sectorId == null)) {
      return 'Choose a job type and sector.';
    }
    if (step == 1 &&
        (_positionId == null || _positionLoading || _positionError != null)) {
      return 'Choose a position and wait for its details to load.';
    }
    if (step == 2) {
      final specs = _rows(_position?['specializations'])
          .where((row) => row['isActive'] != false);
      if (specs.isNotEmpty && _specializations.isEmpty) {
        return 'Choose at least one specialization.';
      }
      final years = int.tryParse(_experience.text.trim());
      if (years == null || years < 0 || years > 80) {
        return 'Enter experience from 0 to 80 years.';
      }
      if (_languages.isEmpty) return 'Choose at least one language.';
    }
    if (step == 3) {
      if (_locations.isEmpty) {
        return 'Add at least one preferred work location.';
      }
      final salary = num.tryParse(_salary.text.trim());
      if (salary == null ||
          !salary.isFinite ||
          salary < 0.01 ||
          salary > 99999999) {
        return 'Enter expected pay between ₹0.01 and ₹99,999,999.';
      }
      if (_notice == 'CUSTOM_DATE' && _availableOn == null) {
        return 'Choose your joining date.';
      }
    }
    return null;
  }

  void _message(String value) =>
      showGxSnack(context, value, type: GxSnackType.error);

  Future<void> _next() async {
    if (_saving || _uploading || _positionLoading) return;
    final issue = _issue(_step);
    if (issue != null) {
      _message(issue);
      return;
    }
    if (_step < 4) {
      setState(() => _step++);
      return;
    }
    await _save();
  }

  String get _profileName => _name.text.trim().isNotEmpty
      ? _name.text.trim()
      : [_positionLabel, if (_locations.isNotEmpty) _locations.first.label]
          .whereType<String>()
          .join(' · ')
          .characters
          .take(100)
          .toString();

  Map<String, dynamic> _draft() {
    final skillNames = _rows(_position?['skills'])
        .where((row) => _skillIds.contains(row['id']))
        .map((row) => '${row['label']}')
        .where((label) => !label.contains(',') && label.length <= 100);
    final names = _skillIds.isEmpty ? _legacySkills : skillNames.toList();
    return {
      'jobType': _positionLabel,
      'sectorId': _sectorId,
      'positionId': _positionId,
      'employmentType': _employment,
      'experienceYears': int.parse(_experience.text.trim()),
      'qualificationId': _qualification,
      'specializationIds': _specializations.toList(),
      'skillIds': _skillIds.toList(),
      'skills': names.take(50).toList(),
      'languageIds': _languages,
      'preferredLocation': _locations.first.label,
      'locationId': _locations.first.id,
      'addressText': _locations.first.label,
      'expectedSalary': num.parse(_salary.text.trim()),
      'expectedSalaryPeriod': _period,
      'salaryNegotiable': _negotiable,
      'noticePeriod': _notice,
      'seekerDetails': {
        'profileName': _profileName,
        'bio': _bio.text.trim(),
        'workMode': _mode,
        'locations': [
          for (final place in _locations) {'id': place.id, 'label': place.label}
        ],
        'availableOn':
            _notice == 'CUSTOM_DATE' ? _dateOnly(_availableOn!) : null,
        'resumeId': _resumeId,
        'resumeName': _resumeName,
      },
    };
  }

  Future<void> _save() async {
    for (var step = 0; step < 4; step++) {
      final issue = _issue(step);
      if (issue != null) {
        setState(() => _step = step);
        _message(issue);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final draft = _draft();
      if (_editing) {
        await repo.updatePreference('${widget.existing!['id']}', draft);
      } else {
        final result = await repo.createPreference(draft);
        if (!mounted) return;
        if (result['needsPayment'] == true) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add a paid profile?'),
              content: Text(
                  'This profile costs ₹${result['fee'] ?? 50} for 30 days of matching.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Back')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue to payment')),
              ],
            ),
          );
          if (!mounted) return;
          if (confirmed == true) {
            await _openPayment(draft);
          } else {
            setState(() => _saving = false);
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _message(_errorMessage(e));
      }
    }
  }

  String _errorMessage(Object e) {
    final data = e is DioException ? e.response?.data : null;
    return data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Could not complete the request. Please try again.';
  }

  Future<void> _openPayment(Map<String, dynamic> draft) async {
    final order = await ref
        .read(matchingRepositoryProvider)
        .createExtraJobTypeOrder(draft);
    if (!mounted) return;
    _orderId = _text(order['orderId']);
    if (_orderId == null) throw StateError('Missing payment order');
    final user = ref.read(currentUserProvider).value;
    _razorpay ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaid)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPayFail);
    _razorpay!.open({
      'key': order['keyId'] ?? AppConfig.razorpayKey,
      'order_id': _orderId,
      'amount': order['amount'],
      'currency': order['currency'] ?? 'INR',
      'name': AppConfig.appName,
      'description': 'Job profile matching · 30 days',
      'timeout': AppConfig.paymentTimeoutSeconds,
      'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
    });
  }

  Future<void> _onPaid(PaymentSuccessResponse result) async {
    if (!mounted) return;
    try {
      if (result.orderId != _orderId || result.paymentId == null) {
        throw StateError('Missing payment reference');
      }
      await ref
          .read(matchingRepositoryProvider)
          .verifyPayment(_orderId!, result.paymentId!);
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _message('Payment confirmation is pending. Check Pending payments.');
      }
    }
  }

  void _onPayFail(PaymentFailureResponse result) {
    if (!mounted) return;
    setState(() => _saving = false);
    _message('Payment did not complete. Resume it from Pending payments.');
  }

  Future<void> _renew() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = widget.existing!;
      await _openPayment({
        ...saved,
        'expectedSalary': num.tryParse('${saved['expectedSalary']}') ?? 0,
        'renewPreferenceId': saved['id'],
      });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _message(_errorMessage(e));
      }
    }
  }

  Future<void> _pickResume() async {
    if (_uploading || _saving) return;
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        _message('Choose a PDF, Word document or supported image up to 5 MB.');
        return;
      }
      final upload = await ref
          .read(matchingRepositoryProvider)
          .uploadSeekerResume(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _resumeId = _text(upload['resumeId']);
        _resumeName =
            _resumeId == null ? null : _text(upload['fileName']) ?? file.name;
      });
    } catch (e) {
      if (mounted) _message(_errorMessage(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _heading(String value) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      );

  Widget _select(
    String label,
    Map<String, String> options,
    String? value,
    ValueChanged<String?> change,
  ) =>
      DropdownButtonFormField<String>(
        key: ValueKey((label, value)),
        initialValue: options.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in options.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value))
        ],
        onChanged: change,
      );

  Map<String, String> _options(String key, String id, [String? saved]) => {
        for (final row in _catalogueRows(key))
          if (row['isActive'] != false || row[id] == saved)
            '${row[id]}': '${row['label']}',
      };

  List<Widget> _typeAndSector() => [
        _heading('Select job type'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final item
              in _options('employmentTypes', 'code', _employment).entries)
            ChoiceChip(
              label: Text(item.value),
              selected: _employment == item.key,
              onSelected: (_) => setState(() => _employment = item.key),
            ),
        ]),
        _heading('Sector / Category'),
        HiringSectorGrid(
          sectors: _catalogueRows('sectors')
              .where(
                  (row) => row['isActive'] != false || row['id'] == _sectorId)
              .toList(),
          selectedId: _sectorId,
          onSelect: (row) => _chooseSector('${row['id']}'),
        ),
      ];

  List<Widget> _positionStep() => [
        Text(_options('sectors', 'id', _sectorId)[_sectorId] ??
            'Select position'),
        HiringPositionSearch(
          key: ValueKey(_sectorId),
          sectorId: _sectorId,
          selectedId: _positionId,
          selectedLabel: _positionLabel,
          onPick: (pick) {
            if (_positionId == pick.id) return;
            setState(() {
              _positionId = pick.id;
              _positionLabel = pick.label;
              _position = null;
              _specializations.clear();
              _skillIds.clear();
              _legacySkills = [];
              _search.clear();
            });
            _loadPosition(pick.id);
          },
        ),
        if (_positionLoading) const LinearProgressIndicator(),
        if (_positionError != null)
          TextButton(
              onPressed: () => _loadPosition(_positionId!),
              child: Text('$_positionError Retry')),
      ];

  Widget _catalogueChips(String key, Set<String> selected,
      {bool search = false}) {
    final query = _search.text.trim().toLowerCase();
    final choices = _rows(_position?[key])
        .where((row) =>
            (row['isActive'] != false || selected.contains(row['id'])) &&
            (!search || '${row['label']}'.toLowerCase().contains(query)))
        .toList();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final row in choices)
        FilterChip(
          label: Text('${row['label']}'),
          selected: selected.contains(row['id']),
          onSelected: (on) => setState(() {
            final id = '${row['id']}';
            if (on) {
              selected.add(id);
            } else {
              selected.remove(id);
            }
          }),
        ),
    ]);
  }

  List<Widget> _requirements() => [
        if (_rows(_position?['specializations']).isNotEmpty) ...[
          _heading(_text(_position?['typeLabel']) ?? 'Specializations'),
          _catalogueChips('specializations', _specializations),
        ],
        const SizedBox(height: 12),
        _select(
            'Qualification (optional)',
            {
              '': 'None',
              ..._options('qualifications', 'id', _qualification),
            },
            _qualification ?? '',
            (value) => setState(() => _qualification = _text(value))),
        const SizedBox(height: 12),
        TextField(
            controller: _experience,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Experience (years)')),
        _heading('Skills'),
        TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Search skills'),
            onChanged: (_) => setState(() {})),
        _catalogueChips('skills', _skillIds, search: true),
        _heading('Languages you speak'),
        HiringLanguageSection(
          selectedIds: _languages,
          catalogRows: _catalogueRows('languages'),
          minSelection: 1,
          restoredDraft: _editing || _languages.isNotEmpty,
          onChanged: (ids) => setState(() => _languages = List.of(ids)),
        ),
        _heading('Short bio (optional)'),
        TextField(
            controller: _bio,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'Tell employers about your experience.')),
      ];

  void _moveLocation(int index, int destination) {
    setState(() {
      final item = _locations.removeAt(index);
      _locations.insert(destination, item);
    });
  }

  Future<void> _chooseNotice(String? value) async {
    if (value == null) return;
    if (value != 'CUSTOM_DATE') {
      setState(() {
        _notice = value;
        _availableOn = null;
      });
      return;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final last = today.add(const Duration(days: 730));
    final saved = _availableOn ?? today;
    final date = await showDatePicker(
        context: context,
        firstDate: today,
        lastDate: last,
        initialDate: saved.isBefore(today)
            ? today
            : (saved.isAfter(last) ? last : saved));
    if (mounted && date != null) {
      setState(() {
        _notice = value;
        _availableOn = date;
      });
    }
  }

  List<Widget> _locationAndPay() => [
        _heading('Preferred work locations (${_locations.length}/5)'),
        const Text(
            'Order your locations by preference. Priority 1 is matched first.'),
        for (var i = 0; i < _locations.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text('${i + 1}'),
            title: Text(_locations[i].label),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: 'Move up',
                  onPressed: i == 0 ? null : () => _moveLocation(i, i - 1),
                  icon: const Icon(Icons.arrow_upward)),
              IconButton(
                  tooltip: 'Move down',
                  onPressed: i + 1 == _locations.length
                      ? null
                      : () => _moveLocation(i, i + 1),
                  icon: const Icon(Icons.arrow_downward)),
              IconButton(
                  tooltip: 'Remove location',
                  onPressed: () => setState(() => _locations.removeAt(i)),
                  icon: const Icon(Icons.close)),
            ]),
          ),
        if (_locations.length < 5)
          HiringLocationSearch(
            key: ValueKey(_locationPickerKey),
            enableGps: true,
            onPick: (pick) {
              if (_locations.any((place) => place.id == pick.id)) {
                _message('That location is already selected.');
                return;
              }
              setState(() {
                _locations.add((id: pick.id, label: pick.label));
                _locationPickerKey++;
              });
            },
          ),
        const SizedBox(height: 12),
        _select(
            'Work mode',
            const {'ONSITE': 'On-site', 'HYBRID': 'Hybrid', 'REMOTE': 'Remote'},
            _mode,
            (value) => setState(() => _mode = value!)),
        const SizedBox(height: 12),
        TextField(
            controller: _salary,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Expected pay (₹)')),
        const SizedBox(height: 12),
        _select('Pay frequency', _options('salaryPeriods', 'code', _period),
            _period, (value) => setState(() => _period = value!)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Salary negotiable'),
            value: _negotiable,
            onChanged: (value) => setState(() => _negotiable = value)),
        _select('Available to join', _joinChoices, _notice, _chooseNotice),
        if (_notice == 'CUSTOM_DATE' && _availableOn != null)
          TextButton(
            onPressed: () => _chooseNotice('CUSTOM_DATE'),
            child: Text('Joining ${_dateOnly(_availableOn!)} · Change'),
          ),
        _heading('Resume (optional)'),
        Text(_resumeName ?? 'PDF, Word, JPG, PNG or WebP up to 5 MB'),
        Row(children: [
          TextButton(
              onPressed: _uploading ? null : _pickResume,
              child: Text(_uploading
                  ? 'Uploading…'
                  : (_resumeId == null ? 'Upload resume' : 'Replace resume'))),
          if (_resumeId != null)
            TextButton(
                onPressed: _uploading
                    ? null
                    : () => setState(() {
                          _resumeId = _resumeName = null;
                        }),
                child: const Text('Remove')),
        ]),
      ];

  String _selectedLabels(String key, Iterable<String> ids,
      {bool position = false}) {
    final rows = position ? _rows(_position?[key]) : _catalogueRows(key);
    final byId = {for (final row in rows) '${row['id']}': '${row['label']}'};
    return ids.map((id) => byId[id] ?? id).join(', ');
  }

  List<Widget> _review() => [
        TextField(
            controller: _name,
            maxLength: 100,
            decoration: InputDecoration(
                labelText: 'Profile name', hintText: _profileName)),
        _heading('Profile summary'),
        Text(
            '${_options('employmentTypes', 'code', _employment)[_employment]} · ${_positionLabel ?? ''}'),
        Text(_options('sectors', 'id', _sectorId)[_sectorId] ?? ''),
        if (_specializations.isNotEmpty)
          Text(
              'Specializations: ${_selectedLabels('specializations', _specializations, position: true)}'),
        if (_qualification != null)
          Text('Qualification: ${_selectedLabels('qualifications', [
                _qualification!
              ])}'),
        Text('Experience: ${_experience.text} years'),
        if (_skillIds.isNotEmpty)
          Text(
              'Skills: ${_selectedLabels('skills', _skillIds, position: true)}'),
        Text('Languages: ${_selectedLabels('languages', _languages)}'),
        if (_bio.text.trim().isNotEmpty) Text(_bio.text.trim()),
        _heading('Work preferences'),
        for (var i = 0; i < _locations.length; i++)
          Text('${i + 1}. ${_locations[i].label}'),
        Text(
            '₹${_salary.text} · ${_options('salaryPeriods', 'code', _period)[_period] ?? _period}${_negotiable ? ' · Negotiable' : ''}'),
        Text('Work mode: $_mode'),
        Text(
            'Available: ${_notice == 'CUSTOM_DATE' && _availableOn != null ? _dateOnly(_availableOn!) : _joinChoices[_notice]}'),
        if (_resumeName != null) Text('Resume: $_resumeName'),
        if (!_editing && widget.freeSlotsLeft == 0)
          const Text(
              'This additional profile costs ₹50 for 30 days of matching.'),
        TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('Edit profile details')),
      ];

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return PopScope<SeekerProfileResult>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, SeekerProfileResult.profiles);
        },
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Profile saved'),
              leading: BackButton(
                  onPressed: () =>
                      Navigator.pop(context, SeekerProfileResult.profiles))),
          body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, size: 50),
                  const SizedBox(height: 16),
                  Text('$_profileName is saved to your Gixbee account.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  GxButton(
                      label: 'View My profiles',
                      onTap: () =>
                          Navigator.pop(context, SeekerProfileResult.profiles)),
                  TextButton(
                      onPressed: () => Navigator.pop(
                          context, SeekerProfileResult.createAnother),
                      child: const Text('Create another profile')),
                ],
              )),
        ),
      );
    }
    return PopScope<SeekerProfileResult>(
      canPop: _step == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Edit job profile' : 'Create job profile'),
          leading: BackButton(
              onPressed: _saving
                  ? () {}
                  : () {
                      if (_step == 0) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _step--);
                      }
                    }),
          actions: [
            TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const PendingPaymentsScreen())),
                child: const Text('Pending payments')),
          ],
        ),
        body: _loadError != null
            ? Center(
                child: TextButton(
                    onPressed: _loadCatalogue,
                    child: Text('$_loadError Retry')))
            : _catalogue == null
                ? const Center(child: CircularProgressIndicator())
                : AbsorbPointer(
                    absorbing: _saving,
                    child: ListView(
                      key: ValueKey(_step),
                      padding: const EdgeInsets.all(20),
                      children: [
                        LinearProgressIndicator(value: (_step + 1) / 5),
                        const SizedBox(height: 12),
                        Text('${_step + 1}/5 · ${_steps[_step]}',
                            style: Theme.of(context).textTheme.titleLarge),
                        if (_step == 0 && widget.existing?['isPaid'] == true)
                          TextButton(
                              onPressed: _renew,
                              child: const Text(
                                  'Renew matching access · ₹50 / 30 days')),
                        ...switch (_step) {
                          0 => _typeAndSector(),
                          1 => _positionStep(),
                          2 => _requirements(),
                          3 => _locationAndPay(),
                          _ => _review(),
                        },
                      ],
                    )),
        bottomNavigationBar: _catalogue == null
            ? null
            : SafeArea(
                child: Padding(
                padding: const EdgeInsets.all(16),
                child: GxButton(
                    label: _step == 4 ? 'Save profile' : 'Continue',
                    loading: _saving,
                    onTap: _saving || _uploading || _positionLoading
                        ? null
                        : _next),
              )),
      ),
    );
  }
}
