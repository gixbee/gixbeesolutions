import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/cities_repository.dart';
import '../../repositories/master_entries_repository.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/talent_repository.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../booking/location_pin_screen.dart';
import 'job_types_screen.dart';

/// A talent profile is ready for Jobs when it is not incomplete and has a
/// role, an employment preference, and a map pin.
bool jobProfileNeedsWizard(Map<String, dynamic> profile) {
  final status = profile['profileStatus']?.toString() ?? '';
  if (status == 'INCOMPLETE') return true;
  final roles = _strings(profile['preferredRoles']);
  final types = _strings(profile['employmentTypes']);
  final lat = profile['lat'];
  final lng = profile['lng'];
  final hasGeo = lat is num && lng is num && !(lat == 0 && lng == 0);
  return roles.isEmpty || types.isEmpty || !hasGeo;
}

List<String> _strings(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
}

const jobCategories = [
  'Electrical',
  'Plumbing',
  'Cleaning',
  'Painting',
  'Carpentry',
  'AC & Appliances',
  'Driving',
  'Delivery',
  'Cooking',
  'Security',
  'Retail & Sales',
  'Office / Admin',
  'Tech & IT',
  'Teaching',
  'Healthcare',
  'Events',
  'Fitness & Yoga',
  'Beauty',
];

const roleSuggestions = {
  'Electrical': ['Electrician', 'Maintenance Electrician', 'Wiring Technician', 'Electrical Helper'],
  'Plumbing': ['Plumber', 'Pipe Fitter', 'Plumbing Helper'],
  'Cleaning': ['Cleaner', 'Housekeeping Staff', 'Deep Cleaning Specialist'],
  'Painting': ['Painter', 'Wall Painter', 'Painter Helper'],
  'Carpentry': ['Carpenter', 'Furniture Carpenter', 'Carpentry Helper'],
  'AC & Appliances': ['AC Technician', 'Appliance Repair Technician'],
  'Driving': ['Driver', 'Delivery Driver', 'Personal Driver'],
  'Delivery': ['Delivery Partner', 'Courier'],
  'Cooking': ['Cook', 'Kitchen Helper', 'Chef'],
  'Security': ['Security Guard', 'Supervisor'],
  'Retail & Sales': ['Sales Associate', 'Cashier', 'Store Helper'],
  'Office / Admin': ['Office Assistant', 'Admin Executive', 'Data Entry'],
  'Tech & IT': ['IT Support', 'Software Developer', 'Technician'],
  'Teaching': ['Teacher', 'Tutor', 'Trainer'],
  'Healthcare': ['Caregiver', 'Nurse Assistant', 'Clinic Helper'],
  'Events': ['Event Staff', 'Event Coordinator'],
  'Fitness & Yoga': ['Yoga Instructor', 'Fitness Trainer'],
  'Beauty': ['Beautician', 'Hair Stylist'],
};

const employmentChoices = [
  ('FT', 'Full-time'),
  ('PT', 'Part-time'),
  ('CONTRACT', 'Contract'),
  ('INTERN', 'Internship'),
  ('GIG', 'Gig'),
];

const experienceChoices = [
  ('Fresher', '0 years'),
  ('Less than 1 year', '0.5 years'),
  ('1–2 years', '1 years'),
  ('3–5 years', '3 years'),
  ('5–10 years', '5 years'),
  ('10+ years', '10 years'),
];

const educationChoices = ['10th', '12th', 'ITI', 'Diploma', 'Degree', 'Postgraduate', 'Other'];

const salaryPeriods = [
  ('HOURLY', 'Hourly'),
  ('DAILY', 'Daily'),
  ('WEEKLY', 'Weekly'),
  ('MONTHLY', 'Monthly'),
  ('PER_JOB', 'Per Job'),
];

const joinChoices = [
  ('IMMEDIATE', 'Immediately'),
  ('DAYS_7', 'Within 7 days'),
  ('DAYS_15', 'Within 15 days'),
  ('DAYS_30', 'Within 30 days'),
  ('CUSTOM_DATE', 'Custom Date'),
];

class SeekerProfileWizard extends ConsumerStatefulWidget {
  const SeekerProfileWizard({super.key});

  @override
  ConsumerState<SeekerProfileWizard> createState() => _SeekerProfileWizardState();
}

class _SeekerProfileWizardState extends ConsumerState<SeekerProfileWizard> {
  int _step = 0;
  bool _saving = false;
  bool _loading = true;

  final _categories = <String>{};
  final _roles = <String>{};
  final _employment = <String>[];
  String? _workMode;
  String? _career;
  final _roleSearch = TextEditingController();

  final _skills = <String>{};
  final _skillSearch = TextEditingController();
  List<String> _catalogSkills = [];
  String? _experienceLabel;
  String? _education;
  String? _resumeUrl;
  String? _resumeName;
  String? _resumeMime;
  String? _resumeUploadedAt;
  bool _uploadingResume = false;

  final _salary = TextEditingController();
  String _salaryPeriod = 'MONTHLY';
  bool _negotiable = false;
  String? _place;
  double? _lat;
  double? _lng;
  double _radius = 25;
  String _availability = 'IMMEDIATE';
  DateTime? _availableOn;
  bool _openToWork = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _roleSearch.dispose();
    _skillSearch.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await ref.read(talentRepositoryProvider).getProfile();
      final roles = _strings(profile['preferredRoles']);
      _categories.addAll(roles.where(jobCategories.contains));
      _roles.addAll(roles.where((role) => !jobCategories.contains(role)));
      _employment.addAll(_strings(profile['employmentTypes']));
      _workMode = profile['preferredWorkMode']?.toString();
      _career = profile['currentStatus']?.toString();
      _skills.addAll(_strings(profile['skills']));
      final experience = profile['experience']?.toString();
      for (final choice in experienceChoices) {
        if (choice.$2 == experience) _experienceLabel = choice.$1;
      }
      final education = _strings(profile['education']);
      if (education.isNotEmpty) _education = education.first;
      _resumeUrl = profile['resumeUrl']?.toString();
      _resumeName = profile['resumeFileName']?.toString();
      _resumeMime = profile['resumeMimeType']?.toString();
      _resumeUploadedAt = profile['resumeUploadedAt']?.toString();
      final salary = profile['expectedSalary'];
      if (salary != null) _salary.text = salary.toString();
      final period = profile['expectedSalaryPeriod']?.toString();
      if (period != null && period.isNotEmpty) _salaryPeriod = period;
      final places = _strings(profile['preferredLocations']);
      if (places.isNotEmpty) _place = places.first;
      _lat = (profile['lat'] as num?)?.toDouble();
      _lng = (profile['lng'] as num?)?.toDouble();
      _radius = (profile['travelRadiusKm'] as num?)?.toDouble() ?? 25;
      if (![5, 10, 25, 50].contains(_radius.round())) _radius = 25;
      final availability = profile['availability']?.toString();
      if (availability != null && availability.isNotEmpty) _availability = availability;
      final rawDate = profile['availableOn']?.toString();
      if (rawDate != null && rawDate.isNotEmpty) {
        _availableOn = DateTime.tryParse(rawDate);
      }
      _openToWork = profile['profileStatus']?.toString() != 'PAUSED';
      await _loadSkills();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSkills() async {
    try {
      final entries = await ref.read(masterEntriesRepositoryProvider).getByType('PRO_SUB_SKILL');
      final labels = entries.map((e) => e.label.trim()).where((e) => e.isNotEmpty).toSet();
      if (mounted) setState(() => _catalogSkills = labels.toList()..sort());
    } catch (_) {}
  }

  List<String> get _suggestedRoles {
    final out = <String>[];
    for (final category in _categories) {
      out.addAll(roleSuggestions[category] ?? const []);
    }
    return out;
  }

  List<String> get _suggestedSkills {
    final query = _skillSearch.text.trim().toLowerCase();
    final source = _catalogSkills.where((skill) {
      if (query.isEmpty) return true;
      return skill.toLowerCase().contains(query);
    });
    return source.take(24).toList();
  }

  String? get _primaryEmployment {
    for (final code in _employment) {
      if (code != 'GIG') return code;
    }
    return null;
  }

  String get _roleName {
    if (_roles.isNotEmpty) return _roles.first;
    if (_categories.isNotEmpty) return _categories.first;
    return 'Job';
  }

  String get _displayName {
    final role = _roleName;
    final code = _employment.isNotEmpty ? _employment.first : null;
    final label = employmentChoices
        .where((choice) => choice.$1 == code)
        .map((choice) => choice.$2)
        .firstOrNull;
    if (label == null) return role;
    return '$role · $label';
  }

  int get _experienceYears {
    final stored = experienceChoices
        .where((choice) => choice.$1 == _experienceLabel)
        .map((choice) => choice.$2)
        .firstOrNull;
    final match = RegExp(r'\d+').firstMatch(stored ?? '');
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_categories.isEmpty && _roles.isEmpty) {
        showGxSnack(context, 'Choose the work you want', type: GxSnackType.error);
        return false;
      }
      if (_employment.isEmpty) {
        showGxSnack(context, 'Choose at least one employment preference', type: GxSnackType.error);
        return false;
      }
      if (_workMode == null) {
        showGxSnack(context, 'Choose a work preference', type: GxSnackType.error);
        return false;
      }
      if (_career == null) {
        showGxSnack(context, 'Choose your career stage', type: GxSnackType.error);
        return false;
      }
    }
    if (_step == 1 && _experienceLabel == null) {
      showGxSnack(context, 'Choose your experience', type: GxSnackType.error);
      return false;
    }
    if (_step == 2) {
      if (_lat == null || _lng == null || (_lat == 0 && _lng == 0)) {
        showGxSnack(context, 'Pin a preferred work location', type: GxSnackType.error);
        return false;
      }
      if (_availability == 'CUSTOM_DATE' && _availableOn == null) {
        showGxSnack(context, 'Choose the date you can join', type: GxSnackType.error);
        return false;
      }
    }
    return true;
  }

  Future<void> _next() async {
    if (!_validateStep()) return;
    if (_step < 2) {
      setState(() => _step += 1);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final roles = {..._categories, ..._roles}.toList();
    final experience = experienceChoices
        .where((choice) => choice.$1 == _experienceLabel)
        .map((choice) => choice.$2)
        .firstOrNull;
    final salary = int.tryParse(_salary.text.trim());
    try {
      await _savePreference(salary);
      await ref.read(talentRepositoryProvider).updateProfile({
        'preferredRoles': roles,
        'skills': _skills.toList(),
        'employmentTypes': _employment,
        'preferredWorkMode': _workMode,
        'currentStatus': _career,
        if (experience != null) 'experience': experience,
        if (_education != null) 'education': [_education],
        'preferredLocations': [if (_place != null && _place!.isNotEmpty) _place],
        'lat': _lat,
        'lng': _lng,
        'travelRadiusKm': _radius,
        if (salary != null) 'expectedSalary': salary,
        'expectedSalaryPeriod': _salaryPeriod,
        'availability': _availability,
        'availableOn': _availability == 'CUSTOM_DATE' && _availableOn != null
            ? _dateOnly(_availableOn!)
            : null,
        'profileStatus': _openToWork ? 'ACTIVE' : 'PAUSED',
        'resumeUrl': _resumeUrl,
        'resumeFileName': _resumeName,
        'resumeMimeType': _resumeMime,
        'resumeUploadedAt': _resumeUploadedAt,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Could not save profile: $e', type: GxSnackType.error);
      setState(() => _saving = false);
    }
  }

  Future<void> _savePreference(int? salary) async {
    final repo = ref.read(matchingRepositoryProvider);
    final prefs = await repo.listPreferences();
    final body = <String, dynamic>{
      'skills': _skills.toList(),
      'preferredLocation': _place ?? '',
      if (salary != null) 'expectedSalary': salary,
      'expectedSalaryPeriod': _salaryPeriod,
      'salaryNegotiable': _negotiable,
      'employmentType': _primaryEmployment,
      'experienceYears': _experienceYears,
      'noticePeriod': _availability,
    };
    final role = _roleName.toLowerCase();
    final match = prefs.where((pref) {
      return '${pref['jobType'] ?? ''}'.toLowerCase() == role;
    }).toList();
    if (match.isNotEmpty) {
      await repo.updatePreference(match.first['id'].toString(), {
        ...body,
        'jobType': _roleName,
      });
      return;
    }
    if (prefs.length == 1) {
      await repo.updatePreference(prefs.first['id'].toString(), {
        ...body,
        'jobType': _roleName,
      });
      return;
    }
    final created = await repo.createPreference({
      ...body,
      'jobType': _roleName,
    });
    if (created['needsPayment'] == true) {
      if (!mounted) return;
      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => JobTypeFormScreen(
            freeSlotsLeft: 0,
            initialPreference: {
              ...body,
              'jobType': _roleName,
              if (_availability == 'CUSTOM_DATE' && _availableOn != null)
                'availableOn': _dateOnly(_availableOn!),
            },
          ),
        ),
      );
      if (paid != true) {
        throw StateError('Payment is required before adding another profile.');
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    final position = await ref.read(locationServiceProvider).getCurrentPosition();
    if (position == null) {
      if (mounted) {
        showGxSnack(context, 'Location is unavailable. Pick it on the map.',
            type: GxSnackType.error);
      }
      return;
    }
    setState(() {
      _lat = position.latitude;
      _lng = position.longitude;
      _place = _place ?? 'Current location';
    });
  }

  Future<void> _pickOnMap() async {
    final pin = await Navigator.push<PinnedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPinScreen(
          initialLat: _lat ?? 8.5241,
          initialLng: _lng ?? 76.9366,
          initialAddress: _place,
        ),
      ),
    );
    if (pin == null) return;
    setState(() {
      _lat = pin.lat;
      _lng = pin.lng;
      _place = pin.address.isNotEmpty ? pin.address : _place;
    });
  }

  Future<void> _pickResume() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() => _uploadingResume = true);
    try {
      final saved = await ref.read(talentRepositoryProvider).uploadResume(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _resumeUrl = saved['fileUrl']?.toString();
        _resumeName = saved['fileName']?.toString() ?? file.name;
        _resumeMime = saved['mimeType']?.toString();
        _resumeUploadedAt = saved['uploadedAt']?.toString();
        _uploadingResume = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingResume = false);
      showGxSnack(context, 'Resume upload failed: $e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        title: const Text('Job Profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Text('${_step + 1}/3',
                    style: TextStyle(
                      color: GixbeeTheme.accentGreen,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 8),
                Text(_heading, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(_subtitle, style: TextStyle(color: context.gx.ink.withValues(alpha: 0.6))),
                const SizedBox(height: 18),
                if (_step == 0) ..._stepWork(),
                if (_step == 1) ..._stepSkills(),
                if (_step == 2) ..._stepPay(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GxButton(
            label: _step < 2 ? 'Continue' : 'Create Profile · Find Jobs',
            loading: _saving,
            accent: GixbeeTheme.accentGreen,
            gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
            onTap: _saving ? null : _next,
          ),
        ),
      ),
    );
  }

  String get _heading => switch (_step) {
        0 => 'What kind of work do you want?',
        1 => 'Your Skills',
        _ => 'Salary & Preferences',
      };

  String get _subtitle => switch (_step) {
        0 => 'Choose the jobs you want Gixbee to match for you.',
        1 => 'Employers see these on your shared profile.',
        _ => 'Pay, location and when you can join.',
      };

  List<Widget> _stepWork() {
    return [
      _label('Categories'),
      _chips(
        jobCategories,
        selected: _categories.contains,
        onTap: (value) => setState(() {
          _categories.contains(value) ? _categories.remove(value) : _categories.add(value);
        }),
      ),
      _label('Preferred role'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final role in {..._suggestedRoles, ..._roles})
            FilterChip(
              label: Text(role),
              selected: _roles.contains(role),
              onSelected: (_) => setState(() {
                _roles.contains(role) ? _roles.remove(role) : _roles.add(role);
              }),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _roleSearch,
              decoration: const InputDecoration(hintText: 'Search or add a role'),
              onSubmitted: _addRole,
            ),
          ),
          IconButton(onPressed: () => _addRole(_roleSearch.text), icon: const Icon(Icons.add)),
        ],
      ),
      _label('Employment preference'),
      _chips(
        [for (final choice in employmentChoices) choice.$2],
        selected: (label) => _employment.contains(_codeFor(label)),
        onTap: (label) => setState(() {
          final code = _codeFor(label);
          _employment.contains(code) ? _employment.remove(code) : _employment.add(code);
        }),
      ),
      _label('Work preference'),
      _chips(
        const ['On-site', 'Remote', 'Hybrid'],
        selected: (label) => _workMode == _modeCode(label),
        onTap: (label) => setState(() => _workMode = _modeCode(label)),
        single: true,
      ),
      _label('Career stage'),
      _chips(
        const ['Student', 'Fresher', 'Experienced'],
        selected: (label) => _career == _careerCode(label),
        onTap: (label) => setState(() => _career = _careerCode(label)),
        single: true,
      ),
    ];
  }

  List<Widget> _stepSkills() {
    return [
      _label('Suggested skills'),
      TextField(
        controller: _skillSearch,
        decoration: const InputDecoration(hintText: 'Search skills'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      _chips(
        _suggestedSkills,
        selected: _skills.contains,
        onTap: (skill) => setState(() {
          _skills.contains(skill) ? _skills.remove(skill) : _skills.add(skill);
        }),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _addSkill(_skillSearch.text),
          icon: const Icon(Icons.add),
          label: const Text('Add skill'),
        ),
      ),
      if (_skills.isNotEmpty)
        Wrap(
          spacing: 6,
          children: [
            for (final skill in _skills)
              InputChip(label: Text(skill), onDeleted: () => setState(() => _skills.remove(skill))),
          ],
        ),
      _label('Experience'),
      _chips(
        [for (final choice in experienceChoices) choice.$1],
        selected: (label) => _experienceLabel == label,
        onTap: (label) => setState(() => _experienceLabel = label),
        single: true,
      ),
      _label('Highest education'),
      _chips(
        educationChoices,
        selected: (label) => _education == label,
        onTap: (label) => setState(() => _education = _education == label ? null : label),
        single: true,
      ),
      _label('Resume / CV'),
      const Text('Resume is optional.'),
      const SizedBox(height: 8),
      if (_resumeName != null) ...[
        Text(_resumeName!, style: const TextStyle(fontWeight: FontWeight.w700)),
        const Text('Uploaded'),
        Row(
          children: [
            TextButton(onPressed: _uploadingResume ? null : _pickResume, child: const Text('Replace')),
            TextButton(
              onPressed: () => setState(() {
                _resumeUrl = null;
                _resumeName = null;
                _resumeMime = null;
                _resumeUploadedAt = null;
              }),
              child: const Text('Remove'),
            ),
          ],
        ),
      ] else
        GxButton(
          label: 'Upload Resume',
          filled: false,
          loading: _uploadingResume,
          accent: GixbeeTheme.accentGreen,
          onTap: _uploadingResume ? null : _pickResume,
        ),
    ];
  }

  List<Widget> _stepPay() {
    final cities = ref.watch(citiesProvider).value ?? const <CityEntry>[];
    return [
      _label('Expected pay'),
      TextField(
        controller: _salary,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixText: '₹ '),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _salaryPeriod,
        decoration: const InputDecoration(labelText: 'Pay type'),
        items: [
          for (final period in salaryPeriods)
            DropdownMenuItem(value: period.$1, child: Text(period.$2)),
        ],
        onChanged: (value) => setState(() => _salaryPeriod = value ?? 'MONTHLY'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Salary negotiable'),
        value: _negotiable,
        activeThumbColor: context.gx.onAccent,
        activeTrackColor: context.gx.accent,
        onChanged: (value) => setState(() => _negotiable = value),
      ),
      _label('Preferred work location'),
      Text(_place ?? 'Location not set'),
      if (_lat != null && _lng != null)
        Text('${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
            style: TextStyle(color: context.gx.ink.withValues(alpha: 0.55), fontSize: 12)),
      Wrap(
        spacing: 8,
        children: [
          TextButton(onPressed: _useCurrentLocation, child: const Text('Use Current Location')),
          TextButton(onPressed: _pickOnMap, child: const Text('Pick on Map')),
        ],
      ),
      TextField(
        decoration: const InputDecoration(hintText: 'Search location'),
        onChanged: (value) {
          final match = cities.cast<CityEntry?>().firstWhere(
                (city) => city!.name.toLowerCase() == value.trim().toLowerCase(),
                orElse: () => null,
              );
          if (match != null && !(match.lat == 0 && match.lng == 0)) {
            setState(() {
              _place = match.displayName;
              _lat = match.lat;
              _lng = match.lng;
            });
          }
        },
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          for (final city in cities.where((city) {
            return city.name.isNotEmpty && !(city.lat == 0 && city.lng == 0);
          }).take(8))
            ActionChip(
              label: Text(city.name),
              onPressed: () => setState(() {
                _place = city.displayName;
                _lat = city.lat;
                _lng = city.lng;
              }),
            ),
        ],
      ),
      _label('Travel radius'),
      _chips(
        const ['5 km', '10 km', '25 km', '50 km'],
        selected: (label) => _radius.round() == int.parse(label.split(' ').first),
        onTap: (label) => setState(() => _radius = double.parse(label.split(' ').first)),
        single: true,
      ),
      _label('Available to Join'),
      _chips(
        [for (final choice in joinChoices) choice.$2],
        selected: (label) => _availability == _joinCode(label),
        onTap: (label) async {
          final code = _joinCode(label);
          if (code == 'CUSTOM_DATE') {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              initialDate: _availableOn ?? DateTime.now(),
            );
            if (picked == null) return;
            setState(() {
              _availability = code;
              _availableOn = picked;
            });
            return;
          }
          setState(() {
            _availability = code;
            _availableOn = null;
          });
        },
        single: true,
      ),
      if (_availability == 'CUSTOM_DATE' && _availableOn != null)
        Text('Joining ${_dateOnly(_availableOn!)}'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Open to Work'),
        subtitle: const Text(
          'When enabled, your profile can be considered for matching opportunities.',
        ),
        value: _openToWork,
        activeThumbColor: context.gx.onAccent,
        activeTrackColor: context.gx.accent,
        onChanged: (value) => setState(() => _openToWork = value),
      ),
    ];
  }

  void _addRole(String raw) {
    final role = raw.trim();
    if (role.isEmpty) return;
    setState(() {
      _roles.add(role);
      _roleSearch.clear();
    });
  }

  void _addSkill(String raw) {
    final skill = raw.trim();
    if (skill.isEmpty || skill.contains(',')) return;
    setState(() {
      _skills.add(skill);
      _skillSearch.clear();
    });
  }

  String _codeFor(String label) =>
      employmentChoices.firstWhere((choice) => choice.$2 == label).$1;

  String _modeCode(String label) => switch (label) {
        'Remote' => 'REMOTE',
        'Hybrid' => 'HYBRID',
        _ => 'ONSITE',
      };

  String _careerCode(String label) => switch (label) {
        'Student' => 'FINAL_YEAR',
        'Fresher' => 'GRADUATE',
        _ => 'EXPERIENCED',
      };

  String _joinCode(String label) =>
      joinChoices.firstWhere((choice) => choice.$2 == label).$1;

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _chips(
    List<String> values, {
    required bool Function(String) selected,
    required void Function(String) onTap,
    bool single = false,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          FilterChip(
            label: Text(value),
            selected: selected(value),
            onSelected: (_) => onTap(value),
            showCheckmark: !single,
          ),
      ],
    );
  }
}

String _dateOnly(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
