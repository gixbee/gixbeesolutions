import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import '../../theme.dart';
import '../../repositories/auth_repository.dart'; // currentUserProvider
import '../../repositories/booking_repository.dart';
import '../../repositories/addresses_repository.dart'; // saved address book
import '../../repositories/cities_repository.dart'; // currentCityProvider
import '../../repositories/worker_repository.dart'; // selectedLocationProvider
import '../../services/location_service.dart';
import '../../shared/models/worker.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../jobs/pro_skill_provider.dart';
import 'no_workers_screen.dart';
import 'waiting_for_worker_screen.dart';
import 'location_pin_screen.dart';
import '../profile/addresses/save_address_bottom_sheet.dart';
import 'instant_help_unblock_screen.dart';
import 'instant_booking_review.dart';

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
  static const _steps = [
    'Location',
    'Presence',
    'Issues',
    'Language',
    'Budget',
    'Review',
  ];

  // v126 c5 language list.
  static const _languages = [
    'Malayalam',
    'Tamil',
    'English',
    'Hindi',
    'Telugu',
    'Kannada',
    'Urdu',
    'Bengali',
    'Marathi',
  ];

  int _step = 0;
  bool _submitting = false;

  // Step 1 — location
  bool _useCurrentLocation = true;
  final _addressCtrl = TextEditingController();

  /// Saved-address id when the user picked one from the address book — sent as
  /// `addressId` so the booking links back to the saved entry.
  String? _selectedAddressId;

  /// Exact coordinates the user confirmed on the pin-drop map for a typed /
  /// different location. When set, these are the authoritative booking
  /// coordinates — no forward-geocoding, no city-centre fallback. Cleared
  /// whenever the address text changes so a stale pin can't attach to a
  /// different address.
  ({double lat, double lng})? _pinnedCoords;

  /// Save the newly typed + pinned address (with its confirmed pin) to the
  /// address book when the request is submitted — next booking is one-tap.
  bool _saveThisAddress = false;

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

  // Step 5 — budget range (₹/hour). Backend Instant Help only accepts a
  // single `amount`; we send the **max** of the range as the billed budget.
  // Instant Help does not filter workers by budget vs their rate.
  static const double _budgetFloor = 50;
  static const double _budgetCeil = 500;
  RangeValues _budgetRange = const RangeValues(100, 250);
  List<Worker>? _nearbyBudgetPros;
  bool _loadingBudgetPros = false;
  Object? _budgetProsError;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedRate > 0) {
      final mid =
          widget.suggestedRate.clamp(_budgetFloor, _budgetCeil).toDouble();
      final lo = (mid * 0.7).clamp(_budgetFloor, mid).toDouble();
      final hi = (mid * 1.3).clamp(mid, _budgetCeil).toDouble();
      _budgetRange = RangeValues(lo.roundToDouble(), hi.roundToDouble());
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
        return _issues.isNotEmpty || _noteCtrl.text.trim().isNotEmpty;
      case 3:
        return _selectedLanguages.isNotEmpty; // demo: select at least one
      case 4:
        return _budgetRange.end >= _budgetRange.start &&
            _budgetRange.end >= _budgetFloor;
      default:
        return true;
    }
  }

  /// Value posted as Instant Help `amount` — the upper end of the range.
  double get _budgetAmount => _budgetRange.end.roundToDouble();

  int get _prosInBudget {
    final pros = _nearbyBudgetPros;
    if (pros == null) return 0;
    return pros.where((pro) {
      return pro.hourlyRate >= _budgetRange.start &&
          pro.hourlyRate <= _budgetRange.end;
    }).length;
  }

  Future<void> _loadBudgetPros() async {
    if (_loadingBudgetPros) return;
    setState(() {
      _loadingBudgetPros = true;
      _budgetProsError = null;
    });
    try {
      final coords = await _resolveCoords();
      if (coords == null) {
        throw StateError('Booking location is unavailable');
      }
      final pros = await ref.read(workerRepositoryProvider).getNearbyWorkers(
            lat: coords.lat,
            lng: coords.lng,
            skill: widget.skill,
            fallbackToAll: false,
          );
      if (!mounted) return;
      setState(() => _nearbyBudgetPros = pros);
    } catch (e) {
      if (mounted) setState(() => _budgetProsError = e);
    } finally {
      if (mounted) setState(() => _loadingBudgetPros = false);
    }
  }

  /// Coordinates for the request.
  /// - "Current location" → the home-picked coords.
  /// - A typed / different location → the pin the user CONFIRMED on the map
  ///   ([_pinnedCoords]). We never silently forward-geocode-with-city-centre-
  ///   fallback here any more: that path put dispatch, routing and GPS strikes
  ///   on the wrong spot (and always fired on web). If somehow no pin was
  ///   captured, we return null and the caller asks the user to drop one.
  Future<({double lat, double lng})?> _resolveCoords() async {
    final loc = ref.read(selectedLocationProvider);
    if (_useCurrentLocation) {
      return loc == null ? null : (lat: loc.lat, lng: loc.lng);
    }
    return _pinnedCoords;
  }

  /// Best-effort STARTING camera target for the pin map (never the booking
  /// coordinate). Tries a forward-geocode of the typed address, then the
  /// home pick, then the serviceable city centre.
  Future<({double lat, double lng})> _mapStartGuess() async {
    final typed = _addressCtrl.text.trim();
    if (!kIsWeb && typed.isNotEmpty) {
      try {
        final results = await Geocoding()
            .locationFromAddress(typed)
            .timeout(const Duration(seconds: 6));
        if (results.isNotEmpty) {
          return (lat: results.first.latitude, lng: results.first.longitude);
        }
      } catch (e) {
        debugPrint('Forward geocode (map start guess) failed: $e');
      }
    }
    final loc = ref.read(selectedLocationProvider);
    if (loc != null) return (lat: loc.lat, lng: loc.lng);
    final city = ref.read(currentCityProvider);
    if (city != null) return (lat: city.lat, lng: city.lng);
    // Absolute last resort — Kerala centre-ish; the user will move the pin.
    return (lat: 8.5241, lng: 76.9366);
  }

  /// Push the pin-drop map for a typed / different location and store the
  /// confirmed coordinates. Returns true when the user confirmed a pin.
  Future<bool> _confirmPinForTypedAddress() async {
    final start = await _mapStartGuess();
    if (!mounted) return false;
    final result = await Navigator.push<PinnedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPinScreen(
          initialLat: start.lat,
          initialLng: start.lng,
          initialAddress: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
        ),
      ),
    );
    if (result == null) return false; // user backed out
    setState(() {
      _pinnedCoords = (lat: result.lat, lng: result.lng);
      // Keep the user's typed text as the human-facing service location, but
      // if they hadn't typed anything, adopt the reverse-geocoded label.
      if (_addressCtrl.text.trim().isEmpty && result.address.isNotEmpty) {
        _addressCtrl.text = result.address;
      }
    });
    // A saved address was selected — persist this confirmed pin onto it
    // (backfills legacy coord-less addresses; refreshes after an Adjust).
    // Fire-and-forget: the booking flow never waits on it.
    final savedId = _selectedAddressId;
    if (savedId != null) {
      ref
          .read(addressesRepositoryProvider)
          .updateCoords(savedId, result.lat, result.lng)
          .then((_) => ref.invalidate(myAddressesProvider))
          .catchError((e) {
        debugPrint('Address pin backfill failed: $e');
      });
    }
    return true;
  }

  /// Full add-address flow FROM INSIDE the booking: pin on the map (with
  /// Ola search) → label it Home/Work/Other with house number → the new
  /// address is saved to the book AND selected for this booking in one go.
  /// (The lighter "save this address" checkbox stays for quick typed spots.)
  Future<void> _addNewSavedAddress() async {
    final start = await _mapStartGuess();
    if (!mounted) return;
    final pinned = await Navigator.push<PinnedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPinScreen(
          initialLat: start.lat,
          initialLng: start.lng,
          initialAddress: null,
        ),
      ),
    );
    if (!mounted || pinned == null) return;

    final saved = await showModalBottomSheet<SavedAddress?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveAddressBottomSheet(pinnedLocation: pinned),
    );
    if (!mounted || saved == null) return;

    setState(() {
      _useCurrentLocation = false;
      _addressCtrl.text = saved.line;
      _selectedAddressId = saved.id;
      _saveThisAddress = false;
      _pinnedCoords = saved.hasPin
          ? (lat: saved.lat!, lng: saved.lng!)
          : (lat: pinned.lat, lng: pinned.lng);
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final coords = await _resolveCoords();
    if (coords == null) {
      if (mounted) {
        showGxSnack(
            context, 'Please pick your location from the home screen first',
            type: GxSnackType.error);
      }
      return;
    }
    final budget = _budgetAmount;
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
      final res =
          await ref.read(bookingRepositoryProvider).sendBroadcastRequest(
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

      // Always show the searching/waiting screen when a booking was created —
      // even if notified == 0 (matching may still be catching up, or the
      // customer should at least see the search UX before the timeout
      // fallback). Only skip straight to NoWorkers when we have no booking.
      if (bookingId == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => NoWorkersScreen(skill: widget.skill)),
        );
        return;
      }

      ref.invalidate(myBookingsProvider);

      // Persist the newly typed + pinned address so the next booking here is
      // one-tap. Fire-and-forget — the request is already on its way.
      if (_saveThisAddress &&
          !_useCurrentLocation &&
          _selectedAddressId == null &&
          _pinnedCoords != null) {
        ref
            .read(addressesRepositoryProvider)
            .add(address, lat: _pinnedCoords!.lat, lng: _pinnedCoords!.lng)
            .then((_) => ref.invalidate(myAddressesProvider))
            .catchError((e) {
          debugPrint('Address save failed: $e');
        });
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingForWorkerScreen(
            bookingId: bookingId,
            skill: widget.skill,
            notifiedCount: notified,
            hourlyRate: budget,
            locationLabel: address,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      // Pull the SERVER's message out of Dio errors — raw `$e` leaks
      // "DioException"/"Exception:" wrappers that read like a crash (this
      // was the client-reported bug). NestJS ValidationPipe sends message
      // as a String or a List<String>.
      String message = 'Something went wrong. Please try again.';
      if (e is DioException) {
        final data = e.response?.data;
        final raw = data is Map ? data['message'] : null;
        if (raw is String && raw.isNotEmpty) {
          message = raw;
        } else if (raw is List && raw.isNotEmpty) {
          message = raw.first.toString();
        } else if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          message = 'No connection. Check your internet and try again.';
        }
      } else {
        message = e.toString().replaceFirst('Exception: ', '');
      }

      // "Nobody live near this spot" is a normal marketplace state, not an
      // error — show the dedicated fallback screen with real next steps
      // (try later / post a job) instead of a red crash-looking toast.
      final lower = message.toLowerCase();
      if (isInstantHelpBlockedError(e)) {
        await openInstantHelpUnblockScreen(context);
        return;
      }
      if (lower.contains('no pros') ||
          lower.contains('no workers') ||
          lower.contains('available near')) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => NoWorkersScreen(skill: widget.skill)),
        );
        return;
      }

      showGxSnack(context, message, type: GxSnackType.error);
    }
  }

  // ── shared UI bits ─────────────────────────────────────────────────────────

  InputDecoration _dec(BuildContext context, String hint, {String? prefix}) =>
      InputDecoration(
        hintText: hint,
        prefixText: prefix,
        prefixStyle: TextStyle(color: context.gx.accentSoft, fontSize: 15),
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

  Widget _chip(BuildContext context, String label, bool selected,
          VoidCallback onTap) =>
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
          sub: _currentAddress.isEmpty
              ? 'Pick on the home screen'
              : _currentAddress,
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
            onChanged: (_) => setState(() {
              // Address text changed — any previously confirmed pin no longer
              // corresponds to what's typed; force a fresh pin-drop.
              _pinnedCoords = null;
              _selectedAddressId = null;
            }),
            style: TextStyle(color: context.gx.ink, fontSize: 14),
            decoration: _dec(context, 'House / street / landmark…'),
          ),
          if (!_useCurrentLocation && _addressCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            // Pin status: confirmed vs still-needed. Continue forces the pin
            // drop when this is unconfirmed (see the scaffold button).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _pinnedCoords != null
                    ? GixbeeTheme.accentGreen.withValues(alpha: 0.1)
                    : context.gx.accentSoft.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _pinnedCoords != null
                        ? GixbeeTheme.accentGreen.withValues(alpha: 0.4)
                        : context.gx.border),
              ),
              child: Row(
                children: [
                  Icon(
                      _pinnedCoords != null
                          ? Icons.check_circle_rounded
                          : Icons.location_on_outlined,
                      size: 18,
                      color: _pinnedCoords != null
                          ? GixbeeTheme.accentGreen
                          : context.gx.accentSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pinnedCoords != null
                          ? 'Exact spot confirmed on map'
                          : 'Pinpoint the exact spot on the map',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.gx.ink.withValues(alpha: 0.75)),
                    ),
                  ),
                  GxPressable(
                    onTap: () => _confirmPinForTypedAddress(),
                    child: Text(
                      _pinnedCoords != null ? 'Adjust' : 'Set pin',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: context.gx.accentSoft),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_useCurrentLocation &&
              _addressCtrl.text.trim().isNotEmpty &&
              _pinnedCoords != null &&
              _selectedAddressId == null) ...[
            const SizedBox(height: 10),
            // New typed address with a confirmed pin — offer to keep both so
            // the next booking here is one-tap (saved on submit).
            GxPressable(
              onTap: () => setState(() => _saveThisAddress = !_saveThisAddress),
              child: Row(
                children: [
                  Icon(
                      _saveThisAddress
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: _saveThisAddress
                          ? context.gx.accentSoft
                          : context.gx.ink.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Save this address & pin for next time',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.gx.ink.withValues(alpha: 0.75)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Saved addresses (address book): tap to fill the field instead of
          // retyping. Restores the feature that lost its home when the old
          // pick-a-pro checkout was removed.
          _savedAddresses(),
        ],
      ],
    );
  }

  /// Chips for the user's saved addresses (GET /addresses) plus an
  /// "Add new address" tile — same address-book flow as the home picker,
  /// reachable right where booking happens. Section renders even with an
  /// empty book so the add-new entry is always discoverable.
  Widget _savedAddresses() {
    final saved = ref.watch(myAddressesProvider);
    final addresses = saved.asData?.value ?? const <SavedAddress>[];
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
              _saveThisAddress = false;
              // Pinned before → reuse the confirmed pin ONE-TAP (no map).
              // Legacy address without coords → the pin confirm is still
              // required, and confirming backfills it for next time.
              _pinnedCoords = a.hasPin ? (lat: a.lat!, lng: a.lng!) : null;
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                color: context.gx.ink.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  if (a.hasPin)
                    // This address carries a confirmed pin — one tap, no map.
                    Icon(Icons.location_on_rounded,
                        size: 14, color: GixbeeTheme.accentGreen),
                ],
              ),
            ),
          ),
        // Add new address — opens the map (with search) then the label
        // sheet; the saved address is immediately selected for this booking.
        GxPressable(
          onTap: _addNewSavedAddress,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: context.gx.card2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: context.gx.accentSoft.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.add_location_alt_outlined,
                    size: 16, color: context.gx.accentSoft),
                const SizedBox(width: 10),
                Text('Add new address',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: context.gx.accentSoft)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepPresence() {
    final user = ref.watch(currentUserProvider).value;
    final myPhone = user?.phone ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Who will be present?',
            'The booking owner receives the OTP. If someone else is present, coordinate the code with them only after the pro arrives.'),
        _optionCard(
          context: context,
          selected: _selfPresent,
          icon: Icons.person_rounded,
          title: 'I will be there myself',
          sub: myPhone.isNotEmpty
              ? 'OTP sent to $myPhone'
              : 'OTP sent to your number',
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
          onChanged: (_) => setState(() {}),
          maxLines: 3,
          style: TextStyle(color: context.gx.ink, fontSize: 14),
          decoration:
              _dec(context, 'Describe the task, access or tools needed…'),
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
    final minR = _budgetRange.start.round();
    final maxR = _budgetRange.end.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Your budget',
            'Set your preferred hourly rate for ${widget.skill}. Minimum charge: 1 hour — after that, billed per elapsed work minute.'),
        _caption(context, 'YOUR BUDGET (₹ / HOUR)'),
        Row(
          children: [
            Expanded(
              child: Text(
                '₹$minR – ₹$maxR / hour',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: context.gx.accentSoft,
                ),
              ),
            ),
            if (widget.suggestedRate > 0)
              Text(
                'Suggested ₹${widget.suggestedRate.round()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.gx.ink.withValues(alpha: 0.45),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: context.gx.accentSoft,
            inactiveTrackColor: context.gx.accentSoft.withValues(alpha: 0.18),
            thumbColor: context.gx.accentSoft,
            overlayColor: context.gx.accentSoft.withValues(alpha: 0.12),
            rangeThumbShape:
                const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
            trackHeight: 3.5,
          ),
          child: RangeSlider(
            values: _budgetRange,
            min: _budgetFloor,
            max: _budgetCeil,
            divisions: ((_budgetCeil - _budgetFloor) / 10).round(),
            labels: RangeLabels('₹$minR', '₹$maxR'),
            onChanged: (v) => setState(() => _budgetRange = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹${_budgetFloor.round()}',
                  style: TextStyle(
                      fontSize: 11,
                      color: context.gx.ink.withValues(alpha: 0.4))),
              Text('₹${_budgetCeil.round()}',
                  style: TextStyle(
                      fontSize: 11,
                      color: context.gx.ink.withValues(alpha: 0.4))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pros are notified by skill and location — not filtered by this '
          'range. Your booking budget is recorded as ₹$maxR/hr (the max).',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: context.gx.ink.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 14),
        _budgetMatchCard(minR: minR, maxR: maxR),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.gx.accentSoft.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: context.gx.accentSoft.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, color: context.gx.accentSoft, size: 22),
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

  Widget _budgetMatchCard({required int minR, required int maxR}) {
    final gx = context.gx;
    final total = _nearbyBudgetPros?.length ?? 0;
    final matches = _prosInBudget;
    final ratio = total == 0 ? 0.0 : matches / total;

    Widget body;
    if (_loadingBudgetPros) {
      body = Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: gx.accentSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Checking live pros near your location…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: gx.ink.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      );
    } else if (_budgetProsError != null) {
      body = Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 22, color: gx.ink.withValues(alpha: 0.45)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live pro count is unavailable right now.',
              style: TextStyle(
                fontSize: 12.5,
                color: gx.ink.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(onPressed: _loadBudgetPros, child: const Text('Retry')),
        ],
      );
    } else if (_nearbyBudgetPros == null) {
      body = const SizedBox.shrink();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: gx.accentSoft.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$matches',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: gx.accentSoft,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      matches == 1
                          ? '1 pro matches your budget'
                          : '$matches pros match your budget',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: gx.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      total == 0
                          ? 'No ${widget.skill} pros are live nearby right now.'
                          : 'Hourly rates between ₹$minR and ₹$maxR · '
                              '$total nearby ${total == 1 ? "pro" : "pros"} total',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: gx.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: gx.accentSoft.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(gx.accentSoft),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.campaign_rounded,
                    size: 15, color: gx.ink.withValues(alpha: 0.45)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'All $total eligible nearby ${total == 1 ? "pro is" : "pros are"} '
                    'notified, even outside this budget range.',
                    style: TextStyle(
                      fontSize: 11,
                      color: gx.ink.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Container(
          key: ValueKey(
              '${_loadingBudgetPros}_${_budgetProsError != null}_${_nearbyBudgetPros != null}_$matches'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: gx.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: gx.accentSoft.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: gx.ink.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: body,
        ),
      ),
    );
  }

  /// Advance one step. On the LOCATION step, a typed / different location
  /// must have a confirmed map pin first — if it doesn't, we open the pin
  /// drop instead of advancing, and only move on once the user confirms.
  Future<void> _advance() async {
    if (_step == 0 && !_useCurrentLocation) {
      if (_pinnedCoords == null) {
        final confirmed = await _confirmPinForTypedAddress();
        if (!confirmed) return; // user backed out of the map — stay put
      }
    }
    if (!mounted) return;
    final nextStep = _step + 1;
    setState(() => _step = nextStep);
    if (nextStep == 4) {
      unawaited(_loadBudgetPros());
    }
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
                    4 => _stepBudget(),
                    _ => InstantBookingReview(
                        skill: widget.skill,
                        address: _useCurrentLocation
                            ? _currentAddress
                            : _addressCtrl.text.trim(),
                        description: [
                          if (_issues.isNotEmpty) _issues.join(', '),
                          if (_noteCtrl.text.trim().isNotEmpty)
                            _noteCtrl.text.trim()
                        ].join(' — '),
                        contact: _selfPresent
                            ? 'Myself'
                            : '${_contactNameCtrl.text.trim()} · ${_contactPhoneCtrl.text.trim()}',
                        languages: _selectedLanguages.toList(),
                        hourlyRate: _budgetAmount,
                      ),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: GxButton(
                  label: isLast
                      ? (_submitting
                          ? 'Notifying nearby pros…'
                          : 'Confirm and find a professional')
                      : (_step == 4 ? 'Review request' : 'Continue'),
                  icon: isLast ? Icons.bolt_rounded : null,
                  onTap: !_canContinue || _submitting
                      ? null
                      : () => isLast ? _submit() : _advance(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
