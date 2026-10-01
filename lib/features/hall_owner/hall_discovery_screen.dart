import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../repositories/auth_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Customer-facing hall discovery (Phase 4). Selection feeds into event planning;
/// booking still goes through hall enquiry + quote accept.
class HallDiscoveryScreen extends ConsumerStatefulWidget {
  const HallDiscoveryScreen({super.key, this.cityId});
  final String? cityId;

  @override
  ConsumerState<HallDiscoveryScreen> createState() => _HallDiscoveryScreenState();
}

class _HallDiscoveryScreenState extends ConsumerState<HallDiscoveryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(
        '/halls/discover',
        queryParameters: {
          if (widget.cityId != null) 'cityId': widget.cityId,
        },
      );
      if (!mounted) return;
      setState(() {
        _items = (res.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, e.message ?? 'Could not load halls',
          type: GxSnackType.error);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a hall')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No halls listed in this city yet'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final h = _items[i];
                    return ListTile(
                      title: Text(
                        '${h['hallName'] ?? 'Hall'} · ${h['businessName'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${h['location'] ?? ''}\n'
                        '${h['timezoneLabel'] ?? 'Times shown in IST (Kolkata)'}',
                      ),
                      isThreeLine: true,
                      onTap: () {
                        showGxSnack(
                          context,
                          'Create an event plan requesting HALL to enquire with this venue.',
                        );
                      },
                    );
                  },
                ),
    );
  }
}
