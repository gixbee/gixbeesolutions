import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/talent_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// v126 Find a Job onboarding wizard (module screens cat → skills → salary →
/// done): a 3-step JOB-SEEKER profile — distinct from RegisterProScreen, which
/// onboards Earn Hourly pros. Saves onto the existing TalentProfile
/// (preferredRoles, currentStatus, skills, expectedSalary,
/// preferredLocations) via POST /talent/profile, and prefills from it so
/// re-runs edit instead of starting blank.
class SeekerProfileWizard extends ConsumerStatefulWidget {
  const SeekerProfileWizard({super.key});

  @override
  ConsumerState<SeekerProfileWizard> createState() =>
      _SeekerProfileWizardState();
}

class _SeekerProfileWizardState extends ConsumerState<SeekerProfileWizard> {
  int _step = 0;
  bool _loading = true;
  bool _submitting = false;

  // Step 1 — what are you looking for
  static const _categories = [
    'Electrician', 'Plumbing', 'Cleaning', 'Painting', 'Carpentry',
    'AC & Appliances', 'Driving', 'Delivery', 'Cooking', 'Security',
    'Retail & Sales', 'Office / Admin', 'Tech & IT', 'Teaching',
    'Healthcare', 'Events', 'Fitness & Yoga', 'Beauty',
  ];
  final Set<String> _selectedRoles = {};
  String? _currentStatus; // FINAL_YEAR | GRADUATE | EXPERIENCED

  // Step 2 — skills
  final Set<String> _skills = {};
  final _skillCtrl = TextEditingController();

  // Step 3 — salary + locations
  final _salaryCtrl = TextEditingController();
  final Set<String> _locations = {};

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _skillCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    try {
      final p = await ref.read(talentRepositoryProvider).getProfile();
      if (!mounted) return;
      setState(() {
        _selectedRoles.addAll(
            (p['preferredRoles'] as List? ?? []).map((e) => e.toString()));
        _skills
            .addAll((p['skills'] as List? ?? []).map((e) => e.toString()));
        _locations.addAll(
            (p['preferredLocations'] as List? ?? []).map((e) => e.toString()));
        _currentStatus = p['currentStatus'] as String?;
        if (p['expectedSalary'] != null) {
          _salaryCtrl.text = '${p['expectedSalary']}';
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('Wizard prefill failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(talentRepositoryProvider).updateProfile({
        'preferredRoles': _selectedRoles.toList(),
        'skills': _skills.toList(),
        'preferredLocations': _locations.toList(),
        if (_currentStatus != null) 'currentStatus': _currentStatus,
        if (int.tryParse(_salaryCtrl.text.trim()) != null)
          'expectedSalary': int.parse(_salaryCtrl.text.trim()),
      });
      ref.invalidate(talentProfileProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGxSnack(context, 'Could not save: $e', type: GxSnackType.error);
    }
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _selectedRoles.isNotEmpty;
      case 1:
        return _skills.isNotEmpty;
      case 2:
        return true; // salary + locations optional
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _header(),
                    if (_step < 3) _progress(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: switch (_step) {
                          0 => _stepCategories(),
                          1 => _stepSkills(),
                          2 => _stepSalaryLocation(),
                          _ => _stepDone(),
                        },
                      ),
                    ),
                    if (_step < 3) _footer(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: context.gx.ink),
            onPressed: () => _step == 0 || _step == 3
                ? Navigator.pop(context)
                : setState(() => _step--),
          ),
          Expanded(
            child: Text(
              'Job profile',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900, color: context.gx.ink),
            ),
          ),
          if (_step < 3)
            Text('${_step + 1}/3',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.gx.ink.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= _step
                      ? GixbeeTheme.accentGreen
                      : context.gx.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: context.gx.ink)),
        const SizedBox(height: 6),
        Text(sub,
            style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.gx.ink.withValues(alpha: 0.55))),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected
                  ? context.gx.onAccent
                  : context.gx.ink.withValues(alpha: 0.75))),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: GixbeeTheme.accentGreen,
      backgroundColor: context.gx.card2,
      side: BorderSide(
          color: selected ? GixbeeTheme.accentGreen : context.gx.border),
    );
  }

  // ── Step 1: categories + status ─────────────────────────────────────────
  Widget _stepCategories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('What are you looking for?',
            'Pick the kinds of work you want alerts for.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _categories)
              _chip(c, _selectedRoles.contains(c), () {
                setState(() => _selectedRoles.contains(c)
                    ? _selectedRoles.remove(c)
                    : _selectedRoles.add(c));
              }),
          ],
        ),
        const SizedBox(height: 24),
        Text('YOUR CURRENT STATUS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.gx.ink.withValues(alpha: 0.45))),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('Final year student', _currentStatus == 'FINAL_YEAR',
                () => setState(() => _currentStatus = 'FINAL_YEAR')),
            _chip('Graduate', _currentStatus == 'GRADUATE',
                () => setState(() => _currentStatus = 'GRADUATE')),
            _chip('Experienced', _currentStatus == 'EXPERIENCED',
                () => setState(() => _currentStatus = 'EXPERIENCED')),
          ],
        ),
      ],
    );
  }

  // ── Step 2: skills ────────────────────────────────────────────────────────
  Widget _stepSkills() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Your skills',
            'Employers see these on your shared profile.'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _skillCtrl,
                style: TextStyle(color: context.gx.ink, fontSize: 14),
                onSubmitted: (_) => _addSkill(),
                decoration: InputDecoration(
                  hintText: 'e.g. Wiring, MS Excel, Driving…',
                  hintStyle:
                      TextStyle(color: context.gx.ink.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: context.gx.card2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: context.gx.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: context.gx.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GxButton(
              label: 'Add',
              expand: false,
              height: 48,
              radius: 14,
              fontSize: 13,
              accent: GixbeeTheme.accentGreen,
              gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
              onTap: _addSkill,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _skills)
              Chip(
                label: Text(s,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink)),
                backgroundColor: context.gx.card2,
                side: BorderSide(color: context.gx.border),
                deleteIcon: Icon(Icons.close_rounded,
                    size: 16, color: context.gx.ink.withValues(alpha: 0.54)),
                onDeleted: () => setState(() => _skills.remove(s)),
              ),
          ],
        ),
      ],
    );
  }

  void _addSkill() {
    final s = _skillCtrl.text.trim();
    if (s.isEmpty) return;
    setState(() {
      _skills.add(s);
      _skillCtrl.clear();
    });
  }

  // ── Step 3: salary + locations ───────────────────────────────────────────
  Widget _stepSalaryLocation() {
    final citiesAsync = ref.watch(citiesProvider);
    final cities = citiesAsync.value ?? const <CityEntry>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Salary & location',
            'Optional — helps match you with the right openings.'),
        Text('EXPECTED SALARY (₹ / MONTH)',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.gx.ink.withValues(alpha: 0.45))),
        const SizedBox(height: 10),
        TextField(
          controller: _salaryCtrl,
          keyboardType: TextInputType.number,
          style: TextStyle(color: context.gx.ink, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'e.g. 18000',
            prefixText: '₹ ',
            prefixStyle:
                const TextStyle(color: GixbeeTheme.accentGreen, fontSize: 15),
            hintStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.3)),
            filled: true,
            fillColor: context.gx.card2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.gx.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.gx.border),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('PREFERRED CITIES',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.gx.ink.withValues(alpha: 0.45))),
        const SizedBox(height: 10),
        if (cities.isEmpty)
          Text('City list unavailable — you can still finish.',
              style: TextStyle(
                  fontSize: 12.5, color: context.gx.ink.withValues(alpha: 0.4)))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in cities)
                _chip(c.name, _locations.contains(c.name), () {
                  setState(() => _locations.contains(c.name)
                      ? _locations.remove(c.name)
                      : _locations.add(c.name));
                }),
            ],
          ),
      ],
    );
  }

  // ── Done ──────────────────────────────────────────────────────────────────
  Widget _stepDone() {
    return Column(
      children: [
        const SizedBox(height: 60),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
          ),
          child: const Icon(Icons.check_circle,
              color: GixbeeTheme.accentGreen, size: 56),
        ),
        const SizedBox(height: 22),
        Text('Profile ready — matching started',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: context.gx.ink)),
        const SizedBox(height: 10),
        Text(
          'New openings that fit your preferences will show up in Job Alerts.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: context.gx.ink.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 36),
        GxButton(
          label: 'See my job alerts',
          accent: GixbeeTheme.accentGreen,
          gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  Widget _footer() {
    final isLast = _step == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: GxButton(
        label: isLast
            ? (_submitting ? 'Saving…' : 'Create profile · Start matching')
            : 'Continue',
        accent: GixbeeTheme.accentGreen,
        gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
        onTap: !_canContinue || _submitting
            ? null
            : () => isLast ? _submit() : setState(() => _step++),
      ),
    );
  }
}
