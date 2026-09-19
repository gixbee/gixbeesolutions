import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../repositories/profile_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../shared/media/profile_photo.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isLoading = false;
  bool _uploadingPhoto = false;
  // Relative `/uploads/...` URL of the (newly picked or existing) avatar.
  String? _photoUrl;
  // Seed the name field + avatar from the live profile exactly once (the
  // provider resolves asynchronously, so we can't read it in initState).
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Uploaded files come back as a relative `/uploads/...` path; prefix the API
  // base so NetworkImage can resolve it (mirrors register_pro._fullUrl).
  String _fullUrl(String path) =>
      path.startsWith('http') ? path : '${AppConfig.baseUrl}$path';

  // Pick → upload → stash the returned URL (persisted on Save Changes).
  Future<void> _pickPhoto() async {
    try {
      final jpeg = await pickWhatsAppProfilePhoto(context);
      if (jpeg == null) return;
      setState(() => _uploadingPhoto = true);
      final url = await ref
          .read(profileRepositoryProvider)
          .uploadImage(jpeg, 'profile.jpg');
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      showGxSnack(context, 'Photo upload failed: $e', type: GxSnackType.error);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Resolve the real authenticated user instead of a placeholder id.
      final user = await ref.read(currentUserProvider.future);
      if (user == null) {
        if (mounted) {
          showGxSnack(context, 'You must be signed in to update your profile.',
              type: GxSnackType.error);
        }
        return;
      }

      await ref.read(profileRepositoryProvider).updateProfile(
        userId: user.id,
        data: {
          'name': _nameController.text,
          // Persist the new avatar only if one was picked this session
          // (backend UsersService.updateProfile saves profileImageUrl).
          if (_photoUrl != null) 'profileImageUrl': _photoUrl,
        },
      );

      // Refresh the cached profile so the new name shows everywhere.
      ref.invalidate(currentUserProvider);

      if (mounted) {
        showGxSnack(context, 'Profile updated successfully!',
            type: GxSnackType.success);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Error updating profile: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pre-fill the name field once the live profile resolves.
    ref.listen(currentUserProvider, (prev, next) {
      next.whenData((user) {
        if (!_seeded && user != null) {
          final name = user.name;
          if (name != null && name.isNotEmpty) _nameController.text = name;
          // Seed the existing avatar so the picker shows current photo.
          final avatar = user.avatar;
          if (avatar != null && avatar.isNotEmpty) _photoUrl = avatar;
          if (name != null && name.isNotEmpty) _seeded = true;
        }
      });
    });
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Theme.of(context).colorScheme.surface, Theme.of(context).colorScheme.surfaceContainerHighest],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: context.gx.accent, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 60,
                            backgroundImage: NetworkImage(
                                (_photoUrl != null && _photoUrl!.isNotEmpty)
                                    ? _fullUrl(_photoUrl!)
                                    : 'https://ui-avatars.com/api/?name=Gixbee+User&background=6200EE&color=fff'),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            backgroundColor: context.gx.accent,
                            radius: 20,
                            child: IconButton(
                              tooltip: 'Change photo',
                              icon: _uploadingPhoto
                                  ? SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          color: context.gx.onAccent,
                                          strokeWidth: 2.5),
                                    )
                                  : Icon(Icons.camera_alt,
                                      color: context.gx.onAccent, size: 20),
                              onPressed: _uploadingPhoto ? null : _pickPhoto,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  GxTextField(
                    label: 'Full Name',
                    hint: 'Enter your full name',
                    controller: _nameController,
                    textInputAction: TextInputAction.done,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Please enter your name'
                        : null,
                  ),
                  const Spacer(),
                  GxPressable(
                    onTap: _isLoading ? null : _save,
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? null
                            : LinearGradient(
                                colors: context.gx.accentGradient),
                        color: _isLoading
                            ? context.gx.ink.withValues(alpha: 0.08)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  color: context.gx.onAccent, strokeWidth: 2.5),
                            )
                          : Text('Save Changes',
                              style: TextStyle(
                                  color: context.gx.onAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
