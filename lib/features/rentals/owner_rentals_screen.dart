import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Owner side of rentals: manage listed items (add/edit/toggle availability,
/// photo upload) and act on incoming reservation requests
/// (confirm → handover → returned; or reject).
class OwnerRentalsScreen extends ConsumerStatefulWidget {
  const OwnerRentalsScreen({super.key});

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
      final items = await repo.getMyItems();
      final reservations = await repo.ownerReservations();
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
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final hourlyCtrl = TextEditingController(
        text: existing == null
            ? ''
            : '${num.tryParse('${existing['hourlyRate']}')?.round() ?? ''}');
    final dailyCtrl = TextEditingController(
        text: existing?['dailyRate'] == null
            ? ''
            : '${num.tryParse('${existing?['dailyRate']}')?.round() ?? ''}');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    String? imageUrl = existing?['imageUrl'] as String?;
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

        Future<void> pickImage() async {
          try {
            final picked = await ImagePicker()
                .pickImage(source: ImageSource.gallery, imageQuality: 80);
            if (picked == null) return;
            setSheet(() => uploading = true);
            final bytes = await picked.readAsBytes();
            final url = await ref
                .read(rentalsRepositoryProvider)
                .uploadImage(bytes, picked.name);
            setSheet(() {
              imageUrl = url;
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
          final name = nameCtrl.text.trim();
          final hourly = double.tryParse(hourlyCtrl.text.trim());
          if (name.isEmpty || hourly == null || hourly <= 0) {
            showGxSnack(ctx, 'Name and hourly rate are required',
                type: GxSnackType.error);
            return;
          }
          setSheet(() => saving = true);
          final daily = double.tryParse(dailyCtrl.text.trim());
          try {
            final repo = ref.read(rentalsRepositoryProvider);
            if (existing == null) {
              await repo.createItem(
                name: name,
                hourlyRate: hourly,
                dailyRate: daily,
                description: descCtrl.text.trim(),
                imageUrl: imageUrl,
              );
            } else {
              await repo.updateItem(existing['id'].toString(), {
                'name': name,
                'hourlyRate': hourly,
                if (daily != null) 'dailyRate': daily,
                'description': descCtrl.text.trim(),
                if (imageUrl != null) 'imageUrl': imageUrl,
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

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: nameCtrl,
                style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                decoration: dec('Item name — e.g. Bosch drill machine')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: hourlyCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                    decoration: dec('₹ / hour')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: dailyCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                    decoration: dec('₹ / day (optional)')),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
                controller: descCtrl,
                maxLines: 2,
                style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                decoration: dec('Description (optional)')),
            const SizedBox(height: 10),
            GxButton(
              label: uploading
                  ? 'Uploading…'
                  : imageUrl == null
                      ? 'Add photo'
                      : 'Change photo ✓',
              filled: false,
              height: 44,
              radius: 12,
              fontSize: 13,
              onTap: uploading ? null : pickImage,
            ),
            const SizedBox(height: 12),
            GxButton(
              label: saving ? 'Saving…' : 'Save item',
              onTap: saving ? null : save,
            ),
            const SizedBox(height: 4),
          ],
        );
      }),
    );

    nameCtrl.dispose();
    hourlyCtrl.dispose();
    dailyCtrl.dispose();
    descCtrl.dispose();
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
      _reservations.where((r) => r['status'] == 'PENDING').length;

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
                        '₹${num.tryParse('${item['hourlyRate']}')?.round()}/hr'
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
              if (status == 'PENDING')
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
              else if (status == 'CONFIRMED')
                GxButton(
                    label: 'Mark handed over',
                    height: 40,
                    radius: 10,
                    fontSize: 12.5,
                    onTap: () => _decide(r, 'start'))
              else if (status == 'ACTIVE')
                GxButton(
                    label: 'Mark returned · complete',
                    height: 40,
                    radius: 10,
                    fontSize: 12.5,
                    onTap: () => _decide(r, 'complete'))
              else
                Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.45))),
            ],
          ),
        );
      },
    );
  }
}
