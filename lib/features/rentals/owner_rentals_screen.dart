import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/dribbble_background.dart';
import 'rental_images.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/models/business.dart';
import '../booking/location_pin_screen.dart';
import 'rental_fulfillment_card.dart';
import 'rental_listing_options.dart';
import '../../shared/widgets/gx_calendar.dart';
import '../../shared/widgets/gx_city_field.dart';
import '../../shared/widgets/gx_time_picker.dart';
import '../profile/addresses/address_line.dart';

/// Owner side of rentals: manage listed items (add/edit/toggle availability,
/// photo upload) and act on incoming reservation requests
/// (confirm → handover → returned; or reject).
class OwnerRentalsScreen extends ConsumerStatefulWidget {
  const OwnerRentalsScreen({super.key, this.businessId});
  final String? businessId;

  @override
  ConsumerState<OwnerRentalsScreen> createState() => _OwnerRentalsScreenState();
}

class _OwnerRentalsScreenState extends ConsumerState<OwnerRentalsScreen> {
  int _tab = 0; // 0 = items, 1 = requests
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _reservations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(rentalsRepositoryProvider);
      final items = await repo.getMyItems(businessId: widget.businessId);
      final reservations = await repo.ownerReservations(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _items = items;
          _reservations = reservations;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Owner rentals load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Add / edit item sheet ──────────────────────────────────────────────────

  Future<void> _openItemSheet({Map<String, dynamic>? existing}) async {
    List<Business> businesses;
    try {
      businesses = (await ref.read(businessRepositoryProvider).getMyBusinesses())
          .where((b) => b.type == 'RENTAL' && b.status == 'VERIFIED').toList();
    } catch (_) {
      if (mounted) showGxSnack(context, 'Unable to load your rental businesses');
      return;
    }
    if (!mounted) return;
    if (businesses.isEmpty && existing == null) {
      showGxSnack(context, 'Add and verify a rental business in My Businesses before listing inventory'); return;
    }
    String? businessId = existing?['businessId'] as String? ?? widget.businessId;
    if (businessId == null && businesses.length == 1) businessId = businesses.first.id;
    final quantityCtrl = TextEditingController(text: '${existing?['quantity'] ?? 1}');
    final pickupCtrl = TextEditingController(text: existing?['pickupAddress'] ??
      businesses.where((b) => b.id == businessId).firstOrNull?.address ?? '');
    final loc = ref.read(selectedLocationProvider);
    var pickupLat = (existing?['pickupLat'] as num?)?.toDouble() ?? loc?.lat;
    var pickupLng = (existing?['pickupLng'] as num?)?.toDouble() ?? loc?.lng;
    final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
    var pickupCity = resolveLiveCity(
      cities,
      ref.read(currentCityProvider),
      lat: pickupLat,
      lng: pickupLng,
    );
    pickupCity ??= matchTypedCity(cities, pickupCtrl.text);
    final cityCtrl = TextEditingController(text: pickupCity?.displayName ?? '');
    final cityFocus = FocusNode();
    final deliveryCtrl = TextEditingController(text: '${existing?['deliveryFee'] ?? 0}');
    final depositCtrl = TextEditingController(text: '${existing?['depositPerUnit'] ?? 0}');
    final advanceCtrl = TextEditingController(text: '${existing?['advanceAmount'] ?? 0}');
    final minimumCtrl = TextEditingController(text: '${existing?['minHoursToRent'] ?? 1}');
    final instructionsCtrl = TextEditingController(text: '${existing?['pickupInstructions'] ?? ''}');
    final lateCtrl = TextEditingController(text: '${existing?['lateFeePerHour'] ?? 0}');
    bool deliveryAvailable = existing?['deliveryAvailable'] == true;
    final existingPercent = num.tryParse('${existing?['advancePercent'] ?? 0}') ?? 0;
    var advanceIsPercent = existingPercent > 0;
    if (advanceIsPercent) {
      advanceCtrl.text = existingPercent == existingPercent.roundToDouble()
          ? '${existingPercent.round()}'
          : '$existingPercent';
    }
    var category = '${existing?['category'] ?? 'OTHER'}';
    var condition = '${existing?['condition'] ?? 'GOOD'}';
    var cancelPolicy = '${existing?['cancellationPolicy'] ?? 'FLEXIBLE'}';
    var weekdays = parseWeekdays(existing?['availableWeekdays']);
    DateTime? availableFrom = parseYmd(existing?['availableFrom']);
    DateTime? availableUntil = parseYmd(existing?['availableUntil']);
    int? slotStart = int.tryParse('${existing?['slotStartMinute'] ?? ''}');
    int? slotEnd = int.tryParse('${existing?['slotEndMinute'] ?? ''}');
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final hourlyCtrl = TextEditingController(
        text: existing == null
            ? ''
            : '${existing['hourlyRate'] ?? ''}');
    final dailyCtrl = TextEditingController(
        text: existing?['dailyRate'] == null
            ? ''
            : '${existing?['dailyRate'] ?? ''}');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    var photos = rentalImageUrls(existing);
    var uploading = false;
    var saving = false;

    await showGxSheet<void>(
      context,
      title: existing == null ? 'List an item' : 'Edit item',
      child: StatefulBuilder(builder: (ctx, setSheet) {
        InputDecoration dec(String hint) => InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: ctx.gx.ink.withValues(alpha: 0.3)),
              filled: true,
              fillColor: ctx.gx.card2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ctx.gx.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ctx.gx.border),
              ),
            );

        const fieldPad = EdgeInsets.fromLTRB(20, 20, 20, 96);

        Future<void> pickImages() async {
          if (photos.length >= kMaxRentalPhotos) {
            showGxSnack(ctx, 'You can add up to $kMaxRentalPhotos photos');
            return;
          }
          try {
            final picked = await ImagePicker().pickMultiImage(
              maxWidth: kPhotoMaxEdge.toDouble(),
              maxHeight: kPhotoMaxEdge.toDouble(),
              imageQuality: 90,
              limit: kMaxRentalPhotos - photos.length,
            );
            if (picked.isEmpty) return;
            setSheet(() => uploading = true);
            final next = [...photos];
            for (final file in picked) {
              if (next.length >= kMaxRentalPhotos) break;
              final bytes = encodeWhatsAppPhotoJpeg(await file.readAsBytes());
              next.add(await ref
                  .read(rentalsRepositoryProvider)
                  .uploadImage(bytes, 'rental.jpg'));
            }
            setSheet(() {
              photos = next;
              uploading = false;
            });
          } catch (e) {
            setSheet(() => uploading = false);
            if (ctx.mounted) {
              showGxSnack(ctx, 'Upload failed: $e', type: GxSnackType.error);
            }
          }
        }

        Future<void> save() async {
          if (saving || uploading) return;
          final name = nameCtrl.text.trim();
          final hourly = double.tryParse(hourlyCtrl.text.trim());
          final quantity = int.tryParse(quantityCtrl.text);
          final minimum = int.tryParse(minimumCtrl.text);
          final delivery = deliveryAvailable
              ? double.tryParse(deliveryCtrl.text)
              : 0.0;
          final deposit = double.tryParse(depositCtrl.text);
          final advance = double.tryParse(advanceCtrl.text);
          final lateFee = double.tryParse(lateCtrl.text);
          if ((slotStart == null) != (slotEnd == null) ||
              (slotStart != null && slotEnd != null && slotEnd! <= slotStart!)) {
            showGxSnack(ctx, 'Set both pickup hours, with end after start — or choose any time of day',
                type: GxSnackType.error);
            return;
          }
          if (name.isEmpty || hourly == null || !hourly.isFinite || hourly <= 0 ||
              businessId == null || pickupCtrl.text.trim().isEmpty || cityCtrl.text.trim().isEmpty || quantity == null || quantity < 1 || quantity > 100000 ||
              minimum == null || minimum < 1 || minimum > 8784 || delivery == null || !delivery.isFinite || delivery < 0 ||
              deposit == null || !deposit.isFinite || deposit < 0 ||
              advance == null || !advance.isFinite || advance < 0 ||
              lateFee == null || !lateFee.isFinite || lateFee < 0 ||
              (advanceIsPercent && advance > 100) ||
              weekdays.isEmpty) {
            showGxSnack(ctx, 'Choose a business and enter valid rates, quantity and pickup details',
                type: GxSnackType.error);
            return;
          }
          setSheet(() => saving = true);
          final daily = double.tryParse(dailyCtrl.text.trim());
          final liveCities = ref.read(citiesProvider).value ?? const <CityEntry>[];
          pickupCity = matchTypedCity(liveCities, cityCtrl.text) ?? pickupCity;
          final cityLabel = pickupCity?.displayName ?? cityCtrl.text.trim();
          final pickupAddress = ensureCityInAddress(pickupCtrl.text, cityLabel);
          try {
            if (pickupCity != null && businessId != null) {
              try {
                await ref
                    .read(businessRepositoryProvider)
                    .updateBusiness(businessId!, {'cityId': pickupCity!.id});
              } catch (_) {}
            }
            final repo = ref.read(rentalsRepositoryProvider);
            if (existing == null) {
              if (pickupLat == null || pickupLng == null) {
                setSheet(() => saving = false);
                showGxSnack(ctx, 'Turn on location so nearby customers can find this item',
                    type: GxSnackType.error);
                return;
              }
              await repo.createItem(
                name: name,
                hourlyRate: hourly,
                dailyRate: daily,
                description: descCtrl.text.trim(),
                imageUrl: photos.isEmpty ? null : photos.first,
                imageUrls: photos,
                businessId: businessId!, quantity: quantity, minHoursToRent: minimum,
                pickupAddress: pickupAddress,
                pickupLat: pickupLat, pickupLng: pickupLng,
                deliveryAvailable: deliveryAvailable,
                deliveryFee: delivery, depositPerUnit: deposit,
                advanceAmount: advanceIsPercent ? 0 : advance,
                advancePercent: advanceIsPercent ? advance : 0,
                pickupInstructions: instructionsCtrl.text.trim(),
                lateFeePerHour: lateFee,
                condition: condition,
                category: category,
                cancellationPolicy: cancelPolicy,
                availableFrom: ymd(availableFrom),
                availableUntil: ymd(availableUntil),
                availableWeekdays: weekdays,
                slotStartMinute: slotStart,
                slotEndMinute: slotEnd,
              );
            } else {
              await repo.updateItem(existing['id'].toString(), {
                'name': name,
                'hourlyRate': hourly,
                'dailyRate': daily,
                'businessId': businessId, 'quantity': quantity, 'minHoursToRent': minimum,
                'pickupAddress': pickupAddress,
                if (pickupLat != null) 'pickupLat': pickupLat,
                if (pickupLng != null) 'pickupLng': pickupLng,
                'deliveryAvailable': deliveryAvailable,
                'deliveryFee': delivery, 'depositPerUnit': deposit,
                'advanceAmount': advanceIsPercent ? 0 : advance,
                'advancePercent': advanceIsPercent ? advance : 0,
                'pickupInstructions': instructionsCtrl.text.trim(),
                'lateFeePerHour': lateFee,
                'condition': condition,
                'category': category,
                'cancellationPolicy': cancelPolicy,
                'availableFrom': ymd(availableFrom),
                'availableUntil': ymd(availableUntil),
                'availableWeekdays': weekdays,
                'slotStartMinute': slotStart,
                'slotEndMinute': slotEnd,
                'description': descCtrl.text.trim(),
                'imageUrl': photos.isEmpty ? null : photos.first,
                'imageUrls': photos,
              });
            }
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } catch (e) {
            setSheet(() => saving = false);
            if (ctx.mounted) {
              showGxSnack(ctx, 'Could not save: $e', type: GxSnackType.error);
            }
          }
        }

        return LayoutBuilder(builder: (_, constraints) {
          final mq = MediaQuery.of(ctx);
          final available = mq.size.height - mq.viewInsets.bottom;
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : available * 0.72;
          return SizedBox(
            height: maxH,
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            if (existing?['businessId'] == null) ...[
              DropdownButtonFormField<String>(initialValue: businesses.any((b) => b.id == businessId) ? businessId : null,
                decoration: dec('Rental business'), items: businesses.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                onChanged: saving ? null : (value) => setSheet(() => businessId = value)),
              const SizedBox(height: 8),
            ],
            TextField(
                controller: nameCtrl,
                scrollPadding: fieldPad,
                style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                decoration: dec('Item name — e.g. Bosch drill machine')),
            const SizedBox(height: 10),
            Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: kRentalCategories.any((c) => c.$1 == category) ? category : 'OTHER',
              decoration: dec('Category'),
              items: kRentalCategories
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                  .toList(),
              onChanged: saving ? null : (v) => setSheet(() => category = v ?? 'OTHER'),
            ),
            const SizedBox(height: 10),
            Text('Item condition', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final c in kRentalConditions)
                ChoiceChip(
                  label: Text(c.$2),
                  selected: condition == c.$1,
                  onSelected: saving ? null : (_) => setSheet(() => condition = c.$1),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: hourlyCtrl,
                    keyboardType: TextInputType.number,
                    scrollPadding: fieldPad,
                    style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                    decoration: dec('₹ / hour')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: dailyCtrl,
                    keyboardType: TextInputType.number,
                    scrollPadding: fieldPad,
                    style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                    decoration: dec('₹ / day (optional)')),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
                controller: descCtrl,
                maxLines: 2,
                scrollPadding: fieldPad,
                style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                decoration: dec('Description (optional)')),
            const SizedBox(height: 8),
            TextField(controller: quantityCtrl, keyboardType: TextInputType.number, scrollPadding: fieldPad, decoration: dec('Units in stock')),
            const SizedBox(height: 8),
            TextField(controller: minimumCtrl, keyboardType: TextInputType.number, scrollPadding: fieldPad, decoration: dec('Minimum rental hours')),
            const SizedBox(height: 12),
            Text('Refundable deposit ₹', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            TextField(controller: depositCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), scrollPadding: fieldPad, decoration: dec('Returned after a good return')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('Booking advance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55)))),
              ChoiceChip(label: const Text('₹'), selected: !advanceIsPercent, onSelected: saving ? null : (_) => setSheet(() => advanceIsPercent = false)),
              const SizedBox(width: 6),
              ChoiceChip(label: const Text('%'), selected: advanceIsPercent, onSelected: saving ? null : (_) => setSheet(() => advanceIsPercent = true)),
            ]),
            const SizedBox(height: 6),
            TextField(
              controller: advanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              scrollPadding: fieldPad,
              decoration: dec(advanceIsPercent ? 'Booking advance %  (0 = 20%)' : 'Booking advance ₹  (0 = 20%)'),
            ),
            const SizedBox(height: 12),
            Text('Late fee / extra-hour charge ₹', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            TextField(controller: lateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), scrollPadding: fieldPad, decoration: dec('₹ per extra hour after booked time')),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Offer delivery'), value: deliveryAvailable,
              onChanged: (value) => setSheet(() => deliveryAvailable = value)),
            if (deliveryAvailable) ...[
              Text('Delivery charge ₹', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
              const SizedBox(height: 6),
              TextField(controller: deliveryCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), scrollPadding: fieldPad, decoration: dec('Delivery charge ₹ per reservation')),
              const SizedBox(height: 8),
            ],
            Text('Cancellation policy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: kRentalCancelPolicies.any((p) => p.$1 == cancelPolicy) ? cancelPolicy : 'FLEXIBLE',
              decoration: dec('Cancellation policy'),
              items: kRentalCancelPolicies
                  .map((p) => DropdownMenuItem(value: p.$1, child: Text(p.$2)))
                  .toList(),
              onChanged: saving ? null : (v) => setSheet(() => cancelPolicy = v ?? 'FLEXIBLE'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(rentalCancelPolicyCopy(cancelPolicy).$2,
                  style: TextStyle(fontSize: 12, height: 1.35, color: ctx.gx.ink.withValues(alpha: 0.5))),
            ),
            const SizedBox(height: 12),
            Text('Rental availability', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _dateTap(ctx, availableFrom == null ? 'Available from' : ymd(availableFrom)!, () async {
                final picked = await showGxCalendar(ctx, title: 'Available from', initialDate: availableFrom, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 366)), accent: GixbeeTheme.accentTeal);
                if (picked != null) setSheet(() => availableFrom = picked);
              })),
              const SizedBox(width: 8),
              Expanded(child: _dateTap(ctx, availableUntil == null ? 'Available until' : ymd(availableUntil)!, () async {
                final picked = await showGxCalendar(ctx, title: 'Available until', initialDate: availableUntil ?? availableFrom, firstDate: availableFrom ?? DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 366)), accent: GixbeeTheme.accentTeal);
                if (picked != null) setSheet(() => availableUntil = picked);
              })),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: saving ? null : () => setSheet(() { availableFrom = null; availableUntil = null; }),
                child: const Text('Clear dates (always)'),
              ),
            ),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final d in kRentalWeekdays)
                FilterChip(
                  label: Text(d.$2),
                  selected: weekdays.contains(d.$1),
                  onSelected: saving ? null : (on) => setSheet(() {
                    weekdays = [...weekdays];
                    if (on) {
                      if (!weekdays.contains(d.$1)) weekdays.add(d.$1);
                    } else {
                      weekdays.remove(d.$1);
                    }
                    weekdays.sort();
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _dateTap(ctx, slotStart == null ? 'Hours from' : rentalMinutesLabel(slotStart), () async {
                final t = await showGxTimePicker(ctx, title: 'Available from', initialTime: slotStart == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay(hour: slotStart! ~/ 60, minute: slotStart! % 60), accent: GixbeeTheme.accentTeal);
                if (t != null) setSheet(() => slotStart = minutesFromHourMinute(t.hour, t.minute));
              })),
              const SizedBox(width: 8),
              Expanded(child: _dateTap(ctx, slotEnd == null ? 'Hours until' : rentalMinutesLabel(slotEnd), () async {
                final t = await showGxTimePicker(ctx, title: 'Available until', initialTime: slotEnd == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay(hour: slotEnd! ~/ 60, minute: slotEnd! % 60), accent: GixbeeTheme.accentTeal);
                if (t != null) setSheet(() => slotEnd = minutesFromHourMinute(t.hour, t.minute));
              })),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: saving ? null : () => setSheet(() { slotStart = null; slotEnd = null; }),
                child: const Text('Any time of day'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: pickupCtrl, maxLines: 2, scrollPadding: fieldPad, decoration: dec('Pickup address')),
            const SizedBox(height: 8),
            GxCityField(
              key: const ValueKey('pickup-city'),
              cities: ref.watch(citiesProvider).value ?? const <CityEntry>[],
              controller: cityCtrl,
              focusNode: cityFocus,
              label: 'City *',
              hint: 'Type city — e.g. Thiruvananthapuram',
              enabled: !saving,
              loading: ref.watch(citiesProvider).isLoading,
              scrollPadding: fieldPad,
              decoration: dec('City *'),
              onSelected: (c) => setSheet(() => pickupCity = c),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final city = ref.read(currentCityProvider);
                      final result = await Navigator.push<PinnedLocation>(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => LocationPinScreen(
                            initialLat: pickupLat ?? loc?.lat ?? city?.lat ?? 8.5241,
                            initialLng: pickupLng ?? loc?.lng ?? city?.lng ?? 76.9366,
                            initialAddress: pickupCtrl.text.trim().isEmpty
                                ? null
                                : pickupCtrl.text.trim(),
                          ),
                        ),
                      );
                      if (result == null) return;
                      setSheet(() {
                        pickupLat = result.lat;
                        pickupLng = result.lng;
                        final live = ref.read(citiesProvider).value ?? const <CityEntry>[];
                        pickupCity = matchTypedCity(live, result.locality ?? '') ??
                            nearestCity(live, result.lat, result.lng);
                        if (pickupCity != null) {
                          cityCtrl.text = pickupCity!.displayName;
                        }
                        var line = result.address.trim();
                        if (line.isEmpty) line = pickupCtrl.text.trim();
                        pickupCtrl.text = ensureCityInAddress(
                          line,
                          pickupCity?.displayName ?? result.locality ?? '',
                        );
                      });
                    },
              icon: Icon(
                pickupLat == null
                    ? Icons.add_location_alt_outlined
                    : Icons.edit_location_alt_outlined,
                size: 18,
              ),
              label: Text(pickupLat == null
                  ? 'Pin pickup on map (city + GPS)'
                  : 'Pickup pinned · tap to change'),
            ),
            const SizedBox(height: 8),
            Text('Pickup instructions (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.gx.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            TextField(controller: instructionsCtrl, maxLines: 2, maxLength: 280, scrollPadding: fieldPad, decoration: dec('Call before pickup, floor / building note')),
            const SizedBox(height: 8),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              resolveProfileImageUrl(photos[i]) ?? photos[i],
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 76,
                                height: 76,
                                color: ctx.gx.card2,
                                child: Icon(Icons.image_outlined,
                                    color: ctx.gx.ink.withValues(alpha: 0.35)),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: uploading
                                  ? null
                                  : () => setSheet(() => photos.removeAt(i)),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (photos.length < kMaxRentalPhotos)
                    GxPressable(
                      onTap: uploading ? null : pickImages,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: ctx.gx.card2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ctx.gx.border),
                        ),
                        child: uploading
                            ? const Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: ctx.gx.ink.withValues(alpha: 0.55)),
                                  const SizedBox(height: 4),
                                  Text(
                                    photos.isEmpty ? 'Add photos' : 'Add',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: ctx.gx.ink
                                            .withValues(alpha: 0.55)),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Up to $kMaxRentalPhotos photos. First photo is the cover.',
              style: TextStyle(
                  fontSize: 11.5,
                  color: ctx.gx.ink.withValues(alpha: 0.45)),
            ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GxButton(
              label: saving ? 'Saving…' : 'Save item',
              onTap: saving || uploading ? null : save,
            ),
          ],
        ),
          );
        });
      }),
    );

    nameCtrl.dispose();
    hourlyCtrl.dispose();
    dailyCtrl.dispose();
    descCtrl.dispose();
    quantityCtrl.dispose(); pickupCtrl.dispose(); cityCtrl.dispose(); cityFocus.dispose(); deliveryCtrl.dispose(); depositCtrl.dispose();
    advanceCtrl.dispose(); minimumCtrl.dispose(); instructionsCtrl.dispose(); lateCtrl.dispose();
  }

  Future<void> _decide(Map<String, dynamic> r, String action) async {
    try {
      await ref
          .read(rentalsRepositoryProvider)
          .decide(r['id'].toString(), action);
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Action failed: $e', type: GxSnackType.error);
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Rent out my items',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                  ],
                ),
              ),
              // Tab pills
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(
                  children: [
                    _tabPill('My items (${_items.length})', 0),
                    const SizedBox(width: 8),
                    _tabPill('Requests (${_pendingCount()})', 1),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _tab == 0 ? _itemsList() : _requestsList(),
                      ),
              ),
              if (_tab == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: GxButton(
                    label: 'List a new item',
                    icon: Icons.add_rounded,
                    onTap: () => _openItemSheet(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _pendingCount() =>
      _reservations.where((r) =>
          r['status'] == 'PENDING' ||
          r['status'] == 'PENDING_OWNER_CONFIRMATION').length;

  Widget _dateTap(BuildContext ctx, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: ctx.gx.card2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ctx.gx.border),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ctx.gx.ink)),
      ),
    );
  }

  Widget _tabPill(String label, int index) {
    final selected = _tab == index;
    return GxPressable(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? GixbeeTheme.accentTeal : context.gx.card2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color:
                  selected ? GixbeeTheme.accentTeal : context.gx.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? context.gx.onAccent
                    : context.gx.ink.withValues(alpha: 0.7))),
      ),
    );
  }

  Widget _itemsList() {
    if (_items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Text('No items yet — list your first one below',
              style: TextStyle(
                  fontSize: 13.5, color: context.gx.ink.withValues(alpha: 0.5))),
        ),
      ]);
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = _items[i];
        final available = item['isAvailable'] == true;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.gx.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gx.border, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['name'] ?? ''}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: context.gx.ink)),
                    const SizedBox(height: 3),
                    Text(
                        '${rentalCategoryLabel('${item['category']}')} · ${rentalConditionLabel('${item['condition']}')}'
                        ' · ₹${num.tryParse('${item['hourlyRate']}')?.round()}/hr'
                        '${item['dailyRate'] != null ? ' · ₹${num.tryParse('${item['dailyRate']}')?.round()}/day' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5, color: GixbeeTheme.accentTeal)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: Icon(Icons.edit_outlined,
                    size: 18, color: context.gx.ink.withValues(alpha: 0.54)),
                onPressed: () => _openItemSheet(existing: item),
              ),
              Switch(
                value: available,
                activeThumbColor: GixbeeTheme.accentTeal,
                onChanged: (v) async {
                  await ref
                      .read(rentalsRepositoryProvider)
                      .updateItem(item['id'].toString(), {'isAvailable': v});
                  _load();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _requestsList() {
    if (_reservations.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Text('No requests yet',
              style: TextStyle(
                  fontSize: 13.5, color: context.gx.ink.withValues(alpha: 0.5))),
        ),
      ]);
    }
    final fmt = DateFormat('d MMM, h:mm a');
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: _reservations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _reservations[i];
        final status = '${r['status'] ?? ''}';
        final item = r['item'] as Map? ?? {};
        final renter = r['renter'] as Map? ?? {};
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.gx.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gx.border, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item['name'] ?? ''} — ${renter['name'] ?? 'Customer'}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink)),
              const SizedBox(height: 4),
              Text(
                '${fmt.format(DateTime.parse('${r['startTime']}').toLocal())}  →  ${fmt.format(DateTime.parse('${r['endTime']}').toLocal())}'
                '   ·   ₹${num.tryParse('${r['totalPrice']}')?.round() ?? r['totalPrice']}',
                style: TextStyle(
                    fontSize: 12.5, color: context.gx.ink.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 10),
              if (status == 'PENDING' || status == 'PENDING_OWNER_CONFIRMATION')
                Row(children: [
                  Expanded(
                    child: GxButton(
                        label: 'Confirm',
                        height: 40,
                        radius: 10,
                        fontSize: 12.5,
                        onTap: () => _decide(r, 'confirm')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GxButton(
                        label: 'Reject',
                        filled: false,
                        height: 40,
                        radius: 10,
                        fontSize: 12.5,
                        onTap: () => _decide(r, 'reject')),
                  ),
                ])
              else
                Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.45))),
              RentalFulfillmentCard(key: ValueKey(r['id']), reservation: r, isOwner: true, onChanged: _load),
            ],
          ),
        );
      },
    );
  }
}
