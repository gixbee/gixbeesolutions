import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' show locationFromAddress;
import '../../theme.dart';
import '../../repositories/auth_repository.dart'; // currentUserProvider
import '../../repositories/booking_repository.dart';
import '../../repositories/addresses_repository.dart'; // saved address book
import '../../repositories/cities_repository.dart'; // currentCityProvider
import '../../repositories/worker_repository.dart'; // selectedLocationProvider
import '../../services/location_service.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../jobs/pro_skill_provider.dart';
import 'no_workers_screen.dart';
import 'waiting_for_worker_screen.dart';

/// Uber/Grab-style instant request — stepped exactly like the client's v126
/// demo (ih module c2–c6): LOCATION → PRESENCE (who receives the arrival
/// OTP) → ISSUES → LANGUAGE → BUDGET → broadcast to all nearby live pros
/// (first to accept wins). Service was already chosen on InstantHelpScreen.
class InstantRequestScreen extends ConsumerStatefulWidget {
  final String skill;

  /// Suggested ₹/hr — average of nearby pros (0 = unknown).
  final double suggestedRate;

  /// Common issues for this trade; self-loaded from the PRO_TRADE master
  /// when empty.
  final List<String> issueOptions;

  const InstantRequestScreen({
    super.key,
    required this.skill,
    this.suggestedRate = 0,
    this.issueOptions = const [],
  });

  @override
  ConsumerState<InstantRequestScreen> createState() =>
      _InstantRequestScreenState();
}

class _InstantRequestScreenState extends ConsumerState<InstantRequestScreen> {
  static const _steps = ['Location', 'Presence', 'Issues', 'Language', 'Budget'];

  // v126 c5 language list.
  static const _languages = [
    'Malayalam', 'Tamil', 'English', 'Hindi', 'Telugu',
    'Kannada', 'Urdu', 'Bengali', 'Marathi',
  ];

  int _step = 0;
  bool _submitting = false;

  // Step 1 — location
  bool _useCurrentLocation = true;
  final _addressCtrl = TextEditingController();
  /// Saved-address id when the user picked one from the address book — sent as
  /// `addressId` so the booking links back to the saved entry.
  String? _selectedAddressId;

  // Step 2 — presence (arrival-OTP recipient)
  bool _selfPresent = true;
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();

  // Step 3 — issues
  List<String> _issueOptions = const [];
  final Set<String> _issues = {};
  final _noteCtrl = TextEditingController();

  // Step 4 — languages (demo requires at least one)
  final Set<String> _selectedLanguages = {};

  // Step 5 — budget
  final _budgetCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.suggestedRate > 0) {
      _budgetCtrl.text = widget.suggestedRate.round().toString();
    }
    _issueOptions = widget.issueOptions;
    if (_issueOptions.isEmpty) _loadIssueOptions();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _noteCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIssueOptions() async {
    try {
      final trades = await ref.read(proTradesProvider.future);
      final match = trades.where((t) =>
          t.name.toLowerCase() == widget.skill.toLowerCase() ||
          widget.skill.toLowerCase().contains(t.name.toLowerCase()));
      if (match.isNotEmpty && mounted) {
        setState(() => _issueOptions = match.first.subSkills);
      }
    } catch (e) {
      debugPrint('Issue options load failed: $e');
    }
  }

  String get _currentAddress {
    final loc = ref.read(selectedLocationProvider);
    final addr = ref.read(currentAddressProvider);
    return loc?.address ?? (addr != 'Select Location' ? addr : '');
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _useCurrentLocation
            ? _currentAddress.isNotEmpty
            : _addressCtrl.text.trim().isNotEmpty;
      case 1:
        return _selfPresent ||
            (_contactNameCtrl.text.trim().isNotEmpty &&
                _contactPhoneCtrl.text.trim().length >= 10);
      case 2:
        return true; // issues optional (note covers "Other")
      case 3:
        return _selectedLanguages.isNotEmpty; // demo: select at least one
      case 4:
        return (double.tryParse(_budgetCtrl.text.trim()) ?? 0) > 0;
      default:
        return true;
    }
  }

  /// Coordinates for the request. "Current location" uses the home-picked
  /// coords; a typed "different location" is forward-geocoded so the pro
  /// matching (GEO search) actually happens around the RIGHT place, with the
  /// serviceable-city centre as fallback when geocoding fails.
  Future<({double lat, double lng})?> _resolveCoords() async {
    final loc = ref.read(selectedLocationProvider);
    if (_useCurrentLocation) {
      return loc == null ? null : (lat: loc.lat, lng: loc.lng);
    }
    final typed = _addressCtrl.text.trim();
    if (!kIsWeb) {
      try {
        final results = await locationFromAddress(typed)
            .timeout(const Duration(seconds: 6));
        if (results.isNotEmpty) {
          return (lat: results.first.latitude, lng: results.first.longitude);
        }
      } catch (e) {
        debugPrint('Forward geocoding failed: $e');
      }
    }
    // Fallback: the selected serviceable city's centre, then the home pick.
    final city = ref.read(currentCityProvider);
    if (city != null) return (lat: city.lat, lng: city.lng);
    return loc == null ? null : (lat: loc.lat, lng: loc.lng);
  }

  Future<void> _submit() async {
    final coords = await _resolveCoords();
    if (coords == null) {
      if (mounted) {
        showGxSnack(context,
            'Please pick your location from the home screen first',
            type: GxSnackType.error);
      }
      return;
    }
    final budget = double.parse(_budgetCtrl.text.trim());
    final address =
        _useCurrentLocation ? _currentAddress : _addressCtrl.text.trim();

    final note = _noteCtrl.text.trim();
    final description = [
      if (_issues.isNotEmpty) _issues.join(', '),
      if (note.isNotEmpty) note,
    ].join(' — ');

    // Presence: OTP recipient. "Myself" = default behaviour (OTP to the
    // booking customer); "someone else" rides the onSiteContact field the
    // backend already persists.
    Map<String, dynamic>? onSiteContact;
    if (!_selfPresent) {
      onSiteContact = {
        'name': _contactNameCtrl.text.trim(),
        'relation': 'On-site contact',
        'phone': _contactPhoneCtrl.text.trim(),
      };
    }

    setState(() => _submitting = true);
    try {
      final res = await ref.read(bookingRepositoryProvider).sendBroadcastRequest(
            skill: widget.skill,
            serviceLocation: address,
            lat: coords.lat,
            lng: coords.lng,
            amount: budget,
            description: description.isEmpty ? null : description,
            preferredLanguages: _selectedLanguages.toList(),
            addressId: _useCurrentLocation ? null : _selectedAddressId,
            onSiteContact: onSiteContact,
          );
      if (!mounted) return;
      final notified = (res['notified'] as num?)?.toInt() ?? 0;
      final bookingId = res['booking']?['id']?.toString();

      if (notified == 0 || bookingId == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => NoWorkersScreen(skill: widget.skill)),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingForWorkerScreen(
            bookingId: bookingId,
            skill: widget.skill,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGxSnack(context, 'Could not send request: $e',
          type: GxSnackType.error);
    }
  }

  // ── shared UI bits ─────────────────────────────────────────────────────────

  InputDecoration _dec(BuildContext context, String hint, {String? prefix}) =>
      InputDecoration(
        hintText: hint,
        prefixText: prefix,
        prefixStyle:
            TextStyle(color: context.gx.accentSoft, fontSize: 15),
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
      );

  Widget _caption(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.gx.ink.withValues(alpha: 0.45))),
      );

  Widget _title(BuildContext context, String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: context.gx.ink)),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.gx.ink.withValues(alpha: 0.55))),
          const SizedBox(height: 18),
        ],
      );

  Widget _optionCard({
    required BuildContext context,
    required bool selected,
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GxPressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? context.gx.accentSoft.withValues(alpha: 0.1)
              : context.gx.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? context.gx.accentSoft : context.gx.border,
              width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected
                    ? context.gx.accentSoft
                    : context.gx.ink.withValues(alpha: 0.35)),
            const SizedBox(width: 12),
            Icon(icon, size: 18, color: context.gx.ink.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.gx.ink)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: context.gx.ink.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
          BuildContext context, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? context.gx.onAccent
                    : context.gx.ink.withValues(alpha: 0.75))),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: context.gx.accentSoft,
        backgroundColor: context.gx.card2,
        side: BorderSide(
            color: selected ? context.gx.accentSoft : context.gx.border),
      );

  // ── steps ──────────────────────────────────────────────────────────────────

  Widget _stepLocation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Where do you need help?',
            'The pro is matched near this spot.'),
        _optionCard(
          context: context,
          selected: _useCurrentLocation,
          icon: Icons.my_location_rounded,
          title: 'Use my current location',
          sub: _currentAddress.isEmpty ? 'Pick on the home screen' : _currentAddress,
          onTap: () => setState(() => _useCurrentLocation = true),
        ),
        _optionCard(
          context: context,
          selected: !_useCurrentLocation,
          icon: Icons.home_work_outlined,
          title: 'A different location',
          sub: "Parent's house, office, etc.",
          onTap: () => setState(() => _useCurrentLocation = false),
        ),
        if (!_useCurrentLocation) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _addressCtrl,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: context.gx.ink, fontSize: 14),
            decoration: _dec(context, 'House / street / landmark…'),
          ),
          // Saved addresses (address book): tap to fill the field instead of
          // retyping. Restores the feature that lost its home when the old
          // pick-a-pro checkout was removed.
          _savedAddresses(),
        ],
      ],
    );
  }

  /// Chips for the user's saved addresses (GET /addresses). Silent when the
  /// user has none saved or the fetch fails.
  Widget _savedAddresses() {
    final saved = ref.watch(myAddressesProvider);
    return saved.maybeWhen(
      data: (addresses) {
        if (addresses.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Text('SAVED ADDRESSES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: context.gx.ink.withValues(alpha: 0.45))),
            const SizedBox(height: 8),
            for (final a in addresses)
              GxPressable(
                onTap: () => setState(() {
                  _addressCtrl.text = a.line;
                  _selectedAddressId = a.id;
                }),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedAddressId == a.id
                        ? context.gx.accentSoft.withValues(alpha: 0.1)
                        : context.gx.card2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _selectedAddressId == a.id
                            ? context.gx.accentSoft
                            : context.gx.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          a.label?.toLowerCase() == 'work'
                              ? Icons.business_center_outlined
                              : Icons.home_outlined,
                          size: 16,
                          color: context.gx.accentSoft),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (a.label != null && a.label!.isNotEmpty)
                              Text(a.label!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: context.gx.ink)),
                            Text(a.line,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.gx.ink
                                        .withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _stepPresence() {
    final user = ref.watch(currentUserProvider).value;
    final myPhone = user?.phone ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Who will be present?',
            'The arrival OTP is sent to whoever is at the location — it confirms the pro really arrived.'),
        _optionCard(
          context: context,
          selected: _selfPresent,
          icon: Icons.person_rounded,
          title: 'I will be there myself',
          sub: myPhone.isNotEmpty ? 'OTP sent to $myPhone' : 'OTP sent to your number',
          onTap: () => setState(() => _selfPresent = true),
        ),
        _optionCard(
          context: context,
          selected: !_selfPresent,
          icon: Icons.family_restroom_rounded,
          title: 'Someone else will be there',
          sub: 'Family member, tenant or friend',
          onTap: () => setState(() => _selfPresent = false),
        ),
        if (!_selfPresent) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _contactNameCtrl,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: context.gx.ink, fontSize: 14),
            decoration: _dec(context, 'Their name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contactPhoneCtrl,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: context.gx.ink, fontSize: 14),
            decoration: _dec(context, 'Their phone number', prefix: '+91 '),
          ),
        ],
      ],
    );
  }

  Widget _stepIssues() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'What is the problem?',
            'Select issues — this is shown to the pros before they accept.'),
        if (_issueOptions.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final issue in _issueOptions)
                _chip(context, issue, _issues.contains(issue), () {
                  setState(() => _issues.contains(issue)
                      ? _issues.remove(issue)
                      : _issues.add(issue));
                }),
            ],
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _noteCtrl,
          maxLines: 3,
          style: TextStyle(color: context.gx.ink, fontSize: 14),
          decoration: _dec(context, 'Add details (optional)…'),
        ),
      ],
    );
  }

  Widget _stepLanguage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Language preference',
            'Which languages do you prefer? Select at least one — the pro should speak your language.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lang in _languages)
              _chip(context, lang, _selectedLanguages.contains(lang), () {
                setState(() => _selectedLanguages.contains(lang)
                    ? _selectedLanguages.remove(lang)
                    : _selectedLanguages.add(lang));
              }),
          ],
        ),
      ],
    );
  }

  Widget _stepBudget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Your budget',
            'Set your preferred hourly rate for ${widget.skill}. Billed per worked hour; paused time is free.'),
        _caption(context, 'YOUR BUDGET (₹ / HOUR)'),
        TextField(
          controller: _budgetCtrl,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.gx.ink, fontSize: 15),
          decoration: _dec(
              context,
              widget.suggestedRate > 0
                  ? 'Suggested: ₹${widget.suggestedRate.round()}'
                  : 'e.g. 150',
              prefix: '₹ '),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.gx.accentSoft.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: context.gx.accentSoft.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded,
                  color: context.gx.accentSoft, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'All nearby ${widget.skill} pros matching your request get '
                  'notified — the first to accept is assigned to you.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.45, color: context.gx.ink),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── scaffold ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _steps.length - 1;
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => _step == 0
                          ? Navigator.pop(context)
                          : setState(() => _step--),
                    ),
                    Expanded(
                      child: Text('${widget.skill} · Instant request',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                    Text('${_step + 1}/${_steps.length}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.gx.ink.withValues(alpha: 0.5))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    for (var i = 0; i < _steps.length; i++) ...[
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step
                                ? context.gx.accentSoft
                                : context.gx.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (i < _steps.length - 1) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: switch (_step) {
                    0 => _stepLocation(),
                    1 => _stepPresence(),
                    2 => _stepIssues(),
                    3 => _stepLanguage(),
                    _ => _stepBudget(),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: GxButton(
                  label: isLast
                      ? (_submitting
                          ? 'Notifying nearby pros…'
                          : 'Notify all nearby pros')
                      : 'Continue',
                  icon: isLast ? Icons.bolt_rounded : null,
                  onTap: !_canContinue || _submitting
                      ? null
                      : () =>
                          isLast ? _submit() : setState(() => _step++),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
