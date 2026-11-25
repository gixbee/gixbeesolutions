import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/business_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';

/// Shop owner dashboard: flash offer, normal offer, and enquire packages.
class ShopOffersScreen extends ConsumerStatefulWidget {
  const ShopOffersScreen({super.key, required this.business});

  final Business business;

  @override
  ConsumerState<ShopOffersScreen> createState() => _ShopOffersScreenState();
}

class _ShopOffersScreenState extends ConsumerState<ShopOffersScreen> {
  final _title = TextEditingController();
  final _code = TextEditingController();
  final _discount = TextEditingController();
  String _kind = 'FLASH';
  bool _saving = false;
  List<Map<String, dynamic>> _offers = const [];
  List<Map<String, dynamic>> _enquiries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(businessRepositoryProvider);
      final offers = await repo.myShopOffers(widget.business.id);
      final enquiries = await repo.shopEnquiries(widget.business.id);
      if (mounted) {
        setState(() {
          _offers = offers;
          _enquiries = enquiries;
        });
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (_saving) return;
    final title = _title.text.trim();
    final code = _code.text.trim();
    if (title.isEmpty || code.isEmpty) {
      showGxSnack(context, 'Add a title and a code');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(businessRepositoryProvider).createShopOffer(
        widget.business.id,
        {
          'kind': _kind,
          'title': title,
          'code': code,
          'discount': _discount.text.trim(),
          if (_kind == 'FLASH')
            'endsAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 12))
                .toIso8601String(),
        },
      );
      _title.clear();
      _code.clear();
      _discount.clear();
      if (mounted) {
        showGxSnack(context, 'Offer saved', type: GxSnackType.success);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      final data = e is DioException ? e.response?.data : null;
      showGxSnack(
        context,
        data is Map && data['message'] != null
            ? '${data['message']}'
            : 'Could not save the offer',
        type: GxSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.business.shopCategory ?? 'Shop';
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(title: Text(widget.business.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$category · ${widget.business.status}',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.65))),
          const SizedBox(height: 8),
          const Text(
            'Flash offers expire after 12 hours. Normal offers stay up. Packages are what customers enquire about. Offers go live after the shop is verified.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'FLASH', label: Text('Flash')),
              ButtonSegment(value: 'NORMAL', label: Text('Normal')),
              ButtonSegment(value: 'PACKAGE', label: Text('Package')),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 12),
          GxTextField(controller: _title, label: 'Title'),
          const SizedBox(height: 8),
          GxTextField(controller: _code, label: 'Code'),
          const SizedBox(height: 8),
          GxTextField(controller: _discount, label: 'Discount or price'),
          const SizedBox(height: 12),
          GxButton(
            label: 'Publish',
            loading: _saving,
            onTap: _publish,
            accent: GixbeeTheme.accentBlue,
          ),
          const SizedBox(height: 20),
          const Text('Your offers',
              style: TextStyle(fontWeight: FontWeight.w800)),
          if (_offers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No offers yet'),
            ),
          for (final offer in _offers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${offer['title']}'),
              subtitle: Text(
                  '${offer['kind']} · ${offer['code']}${offer['discount'] == null ? '' : ' · ${offer['discount']}'}'),
            ),
          const SizedBox(height: 12),
          const Text('Enquiries',
              style: TextStyle(fontWeight: FontWeight.w800)),
          if (_enquiries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No enquiries yet'),
            ),
          for (final enquiry in _enquiries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${enquiry['placeName']}'),
              subtitle: Text(
                  '${enquiry['package'] ?? category}\n${enquiry['message']}'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }
}
