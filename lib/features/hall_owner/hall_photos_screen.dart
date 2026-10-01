import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

class HallPhotosScreen extends ConsumerStatefulWidget {
  const HallPhotosScreen({
    super.key,
    required this.business,
    required this.hallId,
  });
  final Business business;
  final String hallId;

  @override
  ConsumerState<HallPhotosScreen> createState() => _HallPhotosScreenState();
}

class _HallPhotosScreenState extends ConsumerState<HallPhotosScreen> {
  List<Map<String, dynamic>> _media = [];
  String? _cover;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(hallRepositoryProvider);
      final media =
          await repo.listMedia(widget.business.id, widget.hallId);
      final hall =
          await repo.getHall(widget.business.id, widget.hallId);
      if (!mounted) return;
      setState(() {
        _media = media;
        _cover = hall['coverImageUrl'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _pick({bool cover = false}) async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref
          .read(businessRepositoryProvider)
          .uploadImage(bytes, picked.name);
      if (cover) {
        await ref.read(hallRepositoryProvider).patchHall(
              widget.business.id,
              widget.hallId,
              {'coverImageUrl': url},
            );
      } else {
        await ref.read(hallRepositoryProvider).addMedia(
              widget.business.id,
              widget.hallId,
              url,
            );
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hall photos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Cover', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_cover != null)
                  Text(_cover!, style: const TextStyle(fontSize: 12)),
                GxButton(label: 'Set cover photo', onTap: () => _pick(cover: true)),
                const SizedBox(height: 16),
                const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                ..._media.map((m) {
                  return ListTile(
                    title: Text((m['url'] as String?) ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref.read(hallRepositoryProvider).removeMedia(
                              widget.business.id,
                              widget.hallId,
                              m['id'] as String,
                            );
                        _load();
                      },
                    ),
                  );
                }),
                GxButton(label: 'Add gallery photo', onTap: () => _pick()),
              ],
            ),
    );
  }
}
