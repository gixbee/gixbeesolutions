import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../repositories/auth_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/utils/api_error_message.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'auth_chrome.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  Uint8List? _photo;
  String? _uploadedPhotoUrl;
  bool _pickingPhoto = false;
  DateTime? _birthDate;
  String? _gender;
  bool _confirmed = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(FormFieldState<Uint8List> field) async {
    if (_pickingPhoto || _saving) return;
    setState(() => _pickingPhoto = true);
    try {
      final photo = await pickWhatsAppProfilePhoto(context);
      if (!mounted || !field.mounted || photo == null) return;
      _photo = photo;
      _uploadedPhotoUrl = null;
      field.didChange(photo);
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not open that photo. Choose another.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final indiaNow = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
    final today = DateTime(indiaNow.year, indiaNow.month, indiaNow.day);
    final date = await showDatePicker(
      context: context,
      helpText: 'Select your date of birth',
      initialDate: _birthDate ?? DateTime(today.year - 18, 1, 1),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (!mounted || !field.mounted || date == null) return;
    _birthDate = date;
    field.didChange(date);
  }

  Future<void> _continue() async {
    if (_saving || _pickingPhoto || !_formKey.currentState!.validate()) return;
    if (!_confirmed) {
      showGxSnack(context, 'Confirm that your details match your document.');
      return;
    }
    final date = _birthDate!;
    final dateOfBirth = [
      date.year.toString(),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
    ].join('-');
    setState(() => _saving = true);
    try {
      _uploadedPhotoUrl ??= await ref
          .read(profileRepositoryProvider)
          .uploadImage(_photo!, 'profile.jpg');
      if (!mounted) return;
      await ref.read(authRepositoryProvider).completeProfileSetup(
            name: _name.text.trim(),
            dateOfBirth: dateOfBirth,
            gender: _gender!,
            profileImageUrl: _uploadedPhotoUrl!,
          );
      if (mounted) ref.invalidate(currentUserProvider);
    } catch (error) {
      if (mounted) {
        showGxSnack(
          context,
          apiErrorMessage(error, fallback: 'Could not save your profile.'),
          type: GxSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bgBottom,
      body: AuthBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthWordmark(fontSize: 38),
                  const SizedBox(height: 24),
                  Text(
                    'Set up your profile',
                    style: GoogleFonts.outfit(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your details as shown on your Aadhaar or PAN card and add a profile photo. All fields are required.',
                    style: TextStyle(color: palette.sub, height: 1.45),
                  ),
                  const SizedBox(height: 24),
                  FormField<Uint8List>(
                    validator: (photo) =>
                        photo == null ? 'Add a profile photo' : null,
                    builder: (field) => Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          foregroundImage: field.value == null
                              ? null
                              : MemoryImage(field.value!),
                          child: const Icon(Icons.person_outline, size: 36),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving || _pickingPhoto
                              ? null
                              : () => _pickPhoto(field),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(field.value == null
                              ? 'Add profile photo'
                              : 'Change photo'),
                        ),
                        if (field.errorText != null)
                          Text(
                            field.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    maxLength: 150,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the full name on your document'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  FormField<DateTime>(
                    validator: (value) =>
                        value == null ? 'Select your date of birth' : null,
                    builder: (field) => InkWell(
                      onTap: _saving ? null : () => _pickDate(field),
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        isEmpty: field.value == null,
                        decoration: InputDecoration(
                          labelText: 'Date of birth',
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.calendar_month_outlined),
                          errorText: field.errorText,
                        ),
                        child: Text(field.value == null
                            ? ''
                            : MaterialLocalizations.of(context)
                                .formatCompactDate(field.value!)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                      DropdownMenuItem(value: 'MALE', child: Text('Male')),
                      DropdownMenuItem(
                        value: 'TRANSGENDER',
                        child: Text('Transgender'),
                      ),
                      DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                    ],
                    onChanged: _saving ? null : (value) => _gender = value,
                    validator: (value) => value == null
                        ? 'Select the gender shown on your document'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                        'I confirm these details match my document.'),
                    value: _confirmed,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _confirmed = value == true),
                  ),
                  const SizedBox(height: 16),
                  AuthPrimaryButton(
                    label: 'Continue',
                    loading: _saving,
                    onPressed: _continue,
                  ),
                  TextButton(
                    onPressed: _saving || _pickingPhoto
                        ? null
                        : () => forceLogoutToWelcomeFromWidget(ref),
                    child: const Text('Sign out'),
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
