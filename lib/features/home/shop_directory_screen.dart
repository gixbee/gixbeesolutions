import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/business_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import 'offer_categories.dart';

/// Gym, clinic, and shop lists opened from Plan an Event and Today's Offers.
/// Only verified shop businesses from the API are listed.
class ShopDirectoryScreen extends ConsumerWidget {
  const ShopDirectoryScreen({super.key, required this.category});

  final OfferCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(_shopPlacesProvider(category.id));
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(title: Text(category.id)),
      body: places.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _EmptyDirectory(),
        data: (rows) => rows.isEmpty
            ? const _EmptyDirectory()
            : _PlaceList(category: category, places: rows),
      ),
    );
  }
}

class _EmptyDirectory extends StatelessWidget {
  const _EmptyDirectory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No verified listings in this category yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

final _shopPlacesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, category) {
  return ref.watch(businessRepositoryProvider).shopDirectory(category);
});

class _PlaceList extends StatelessWidget {
  const _PlaceList({required this.category, required this.places});

  final OfferCategory category;
  final List<Map<String, dynamic>> places;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: places.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final place = places[index];
        return Material(
          color: context.gx.card,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            title: Text(place['name']?.toString() ?? 'Shop',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(place['location']?.toString() ?? category.id),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PlaceDetail(
                  category: category,
                  place: place,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaceDetail extends ConsumerStatefulWidget {
  const _PlaceDetail({required this.category, required this.place});

  final OfferCategory category;
  final Map<String, dynamic> place;

  @override
  ConsumerState<_PlaceDetail> createState() => _PlaceDetailState();
}

class _PlaceDetailState extends ConsumerState<_PlaceDetail> {
  final _message = TextEditingController();
  String? _package;
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  List<String> get _packages {
    final raw = widget.place['packages'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .map((row) => row is Map ? '${row['title']}' : '$row')
          .where((title) => title.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    if (message.isEmpty || _sending) {
      showGxSnack(context, 'Add a short message for the business');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(businessRepositoryProvider).sendShopEnquiry({
        'businessId': widget.place['id'],
        'placeName': widget.place['name'],
        'category': widget.category.id,
        if (_package != null) 'package': _package,
        'message': message,
      });
      if (!mounted) return;
      showGxSnack(context, 'Enquiry sent', type: GxSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final data = e is DioException ? e.response?.data : null;
      final text = data is Map && data['message'] != null
          ? '${data['message']}'
          : 'Could not send the enquiry';
      showGxSnack(context, text, type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = switch (widget.category.kind) {
      'gym' => 'membership',
      'clinic' => 'treatment',
      _ => 'package',
    };
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(title: Text(widget.place['name']?.toString() ?? 'Shop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.place['location']?.toString() ?? '',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7))),
          if ((widget.place['description']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(widget.place['description'].toString()),
          ],
          if (_packages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Choose a $noun',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _package,
              onChanged: (value) => setState(() => _package = value),
              child: Column(
                children: [
                  for (final package in _packages)
                    RadioListTile<String>(
                      value: package,
                      title: Text(package),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          GxTextField(
            controller: _message,
            label: 'Message',
            hint: 'Dates, group size, or what you need',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          GxButton(
            label: 'Send enquiry',
            loading: _sending,
            onTap: _send,
            accent: GixbeeTheme.accentBlue,
          ),
          const SizedBox(height: 8),
          Text(
            'Enquire only. Nothing is booked or paid in the app.',
            style: TextStyle(color: context.gx.ink.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}
