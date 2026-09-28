import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import '../profile/addresses/address_line.dart';
import 'hiring_application_status_screen.dart';
import 'hiring_application_submitted_screen.dart';
import 'hiring_listing.dart';

class HiringBusinessVerificationScreen extends ConsumerStatefulWidget {
  final HiringListingDraft draft;

  const HiringBusinessVerificationScreen({super.key, required this.draft});

  @override
  ConsumerState<HiringBusinessVerificationScreen> createState() =>
      _HiringBusinessVerificationScreenState();
}

class _HiringBusinessVerificationScreenState
    extends ConsumerState<HiringBusinessVerificationScreen> {
  final _regNumberCtrl = TextEditingController();
  final _workEmailCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _regTypeCtrl = TextEditingController();
  final _otherTypeCtrl = TextEditingController();
  bool _uploadingDoc = false;
  bool _isSubmitting = false;

  HiringListingDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _regNumberCtrl.text = draft.registrationNumber;
    _workEmailCtrl.text = draft.workEmail;
    _roleCtrl.text = draft.roleInBusiness ?? '';
    _regTypeCtrl.text = draft.registrationType ?? '';
    _otherTypeCtrl.text = draft.otherDocumentType;
    _workEmailCtrl.addListener(_onWorkEmailChanged);
  }

  void _onWorkEmailChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _workEmailCtrl.removeListener(_onWorkEmailChanged);
    _regNumberCtrl.dispose();
    _workEmailCtrl.dispose();
    _roleCtrl.dispose();
    _regTypeCtrl.dispose();
    _otherTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOption({
    required String title,
    required List<String> options,
    required void Function(String) onPick,
  }) async {
    final picked = await showGxSheet<String>(
      context,
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ListTile(
              title: Text(option,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() => onPick(picked));
    }
  }

  Future<void> _chooseDocumentSource() async {
    if (_uploadingDoc) return;
    final choice = await showGxSheet<String>(
      context,
      title: 'Upload Registration Document',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: GixbeeTheme.accentBlue),
            title: const Text('Photo (JPG, PNG)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, 'photo'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined,
                color: GixbeeTheme.accentBlue),
            title: const Text('File (PDF, JPG, PNG)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, 'file'),
          ),
        ],
      ),
    );
    if (choice == 'photo') {
      await _pickPhoto();
    } else if (choice == 'file') {
      await _pickFile();
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (x == null) return;
      await _uploadBytes(await x.readAsBytes(), x.name);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Document upload failed: $e',
          type: GxSnackType.error);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        showGxSnack(context, 'Could not read that file',
            type: GxSnackType.error);
        return;
      }
      await _uploadBytes(bytes, file.name);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Document upload failed: $e',
          type: GxSnackType.error);
    }
  }

  Future<void> _uploadBytes(List<int> bytes, String name) async {
    if (bytes.length > 5 * 1024 * 1024) {
      if (!mounted) return;
      showGxSnack(context, 'Document must be 5MB or smaller',
          type: GxSnackType.error);
      return;
    }
    setState(() => _uploadingDoc = true);
    try {
      final url =
          await ref.read(businessRepositoryProvider).uploadImage(bytes, name);
      if (!mounted) return;
      setState(() {
        draft.documentUrl = url;
        draft.documentName = name;
        _uploadingDoc = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingDoc = false);
      showGxSnack(context, 'Document upload failed: $e',
          type: GxSnackType.error);
    }
  }

  void _removeDocument() {
    setState(() {
      draft.documentUrl = null;
      draft.documentName = null;
    });
  }

  Future<void> _submit() async {
    if (draft.roleInBusiness == null || draft.roleInBusiness!.isEmpty) {
      showGxSnack(context, 'Select your role in the business');
      return;
    }
    if (!draft.authorised) {
      showGxSnack(context,
          'Confirm that you are authorised to represent this business');
      return;
    }
    final workEmail = _workEmailCtrl.text.trim();
    if (workEmail.isNotEmpty && !workEmail.contains('@')) {
      showGxSnack(context, 'Enter a valid work email, or leave it blank');
      return;
    }

    setState(() => _isSubmitting = true);
    draft.registrationNumber = _regNumberCtrl.text.trim();
    draft.otherDocumentType = _otherTypeCtrl.text.trim();
    draft.workEmail = workEmail;

    try {
      Business saved;
      if (draft.isResubmit) {
        saved = await ref.read(businessRepositoryProvider).updateBusiness(
          draft.existingBusinessId!,
          {
            'documentUrl': draft.documentUrl,
            'hiringProfile': draft.toProfileJson(),
          },
        );
      } else {
        var address = draft.address;
        final cityLabel = draft.city;
        if (cityLabel.isNotEmpty &&
            !address.toLowerCase().contains(cityLabel.toLowerCase())) {
          address = ensureCityInAddress(address, cityLabel);
        }
        String? cityId = draft.cityId;
        try {
          final cities = await ref.read(citiesProvider.future);
          final matched = matchTypedCity(cities, cityLabel);
          cityId = matched?.id ?? cityId;
        } catch (_) {}

        saved = await ref.read(businessRepositoryProvider).registerBusiness(
              Business(
                id: '',
                name: draft.name,
                type: 'HIRING',
                description: draft.description,
                specialty: draft.industries.join(', '),
                phone: draft.phone,
                address: address,
                documentUrl: draft.documentUrl,
                cityId: cityId,
                ownerId: '',
                status: 'PENDING',
                hiringProfile: draft.toProfileJson(),
              ),
            );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HiringApplicationSubmittedScreen(business: saved),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String msg = 'Could not save the business. Please try again.';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['message'] != null) {
          msg = data['message'].toString();
        }
      }
      showGxSnack(context, msg, type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool get _domainMatched =>
      hiringDomainMatched(_workEmailCtrl.text, draft.email);

  String get _docStatusLabel {
    if (draft.documentUrl != null && draft.documentUrl!.isNotEmpty) {
      return 'Uploaded';
    }
    return 'Pending / Not Provided';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasType = (draft.registrationType ?? '').isNotEmpty;
    final isOther = draft.registrationType == 'Other';
    final uploaded = draft.documentUrl != null && draft.documentUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                primary: true,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: GixbeeTheme.accentBlue
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.verified_user_outlined,
                                color: GixbeeTheme.accentBlue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Verify your business',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: context.gx.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Verification helps candidates know they are dealing with a genuine employer.',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'YOUR ROLE'),
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GxTextField(
                            controller: _roleCtrl,
                            label: 'Your Role in Business *',
                            hint: 'Select role',
                            prefixIcon: Icons.person_outline,
                            suffixIcon: Icons.keyboard_arrow_down_rounded,
                            readOnly: true,
                            accent: GixbeeTheme.accentBlue,
                            blur: false,
                            onTap: () => _pickOption(
                              title: 'Your Role in Business',
                              options: hiringRoles,
                              onPick: (v) {
                                draft.roleInBusiness = v;
                                _roleCtrl.text = v;
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          _helper(context,
                              'This helps us confirm that you are allowed to represent the business.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'BUSINESS REGISTRATION'),
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GxTextField(
                            controller: _regTypeCtrl,
                            label: 'Registration Type',
                            hint: 'Optional',
                            prefixIcon: Icons.assignment_outlined,
                            suffixIcon: Icons.keyboard_arrow_down_rounded,
                            readOnly: true,
                            accent: GixbeeTheme.accentBlue,
                            blur: false,
                            onTap: () => _pickOption(
                              title: 'Registration Type',
                              options: hiringRegistrationTypes,
                              onPick: (v) {
                                draft.registrationType = v;
                                _regTypeCtrl.text = v;
                                if (v != 'Other') {
                                  draft.otherDocumentType = '';
                                  _otherTypeCtrl.clear();
                                }
                              },
                            ),
                          ),
                          if (hasType) ...[
                            const SizedBox(height: 14),
                            GxTextField(
                              controller: _regNumberCtrl,
                              label: 'Registration Number',
                              hint: 'Enter registration number',
                              prefixIcon: Icons.tag_outlined,
                              accent: GixbeeTheme.accentBlue,
                              blur: false,
                            ),
                          ],
                          if (isOther) ...[
                            const SizedBox(height: 14),
                            GxTextField(
                              controller: _otherTypeCtrl,
                              label: 'Document Type / Name',
                              hint: 'Enter document type',
                              prefixIcon: Icons.description_outlined,
                              accent: GixbeeTheme.accentBlue,
                              blur: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'DOCUMENT UPLOAD'),
                    _sectionCard(
                      child: uploaded
                          ? _uploadedDoc(context)
                          : GxPressable(
                              onTap: _uploadingDoc ? null : _chooseDocumentSource,
                              child: Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 22),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: cs.outlineVariant
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  children: [
                                    if (_uploadingDoc)
                                      const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor: AlwaysStoppedAnimation(
                                                GixbeeTheme.accentBlue)),
                                      )
                                    else
                                      const Icon(Icons.upload_file_rounded,
                                          color: GixbeeTheme.accentBlue,
                                          size: 32),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Upload Registration Document',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: GixbeeTheme.accentBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'JPG, PNG or PDF up to 5MB',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Optional for eligible small businesses',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.85),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'WORK EMAIL'),
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GxTextField(
                            controller: _workEmailCtrl,
                            label: 'Work Email',
                            hint: 'e.g. hr@company.com',
                            prefixIcon: Icons.alternate_email_rounded,
                            suffix: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                'Optional',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            accent: GixbeeTheme.accentBlue,
                            blur: false,
                          ),
                          const SizedBox(height: 8),
                          _helper(context,
                              'A company email may help us verify your business faster.'),
                          if (_domainMatched) ...[
                            const SizedBox(height: 10),
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 16, color: GixbeeTheme.accentGreen),
                                SizedBox(width: 6),
                                Text(
                                  'Domain matched ✓',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: GixbeeTheme.accentGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'VERIFICATION SUMMARY'),
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verification Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: context.gx.ink,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _summaryRow(context, 'Phone Verified',
                              done: draft.phoneVerified),
                          _summaryRow(context, 'Business Details', done: true),
                          _summaryRow(context, 'Location Added',
                              done: draft.lat != null && draft.lng != null),
                          _summaryRow(context, 'Registration Document',
                              done: uploaded, pendingLabel: _docStatusLabel),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'AUTHORISATION'),
                    _sectionCard(
                      child: GxPressable(
                        onTap: () => setState(
                            () => draft.authorised = !draft.authorised),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              draft.authorised
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: draft.authorised
                                  ? GixbeeTheme.accentBlue
                                  : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'I confirm that I am authorised to represent this business and the information provided is accurate.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  height: 1.4,
                                  color: context.gx.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GixbeeTheme.accentBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                GixbeeTheme.accentBlue.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 16,
                              color: GixbeeTheme.accentBlue
                                  .withValues(alpha: 0.9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your uploaded documents are used only for verification and are not shown publicly to candidates.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
        ),
        child: SafeArea(
          child: GxButton(
            label: 'Submit Application',
            onTap: (draft.authorised && !_isSubmitting) ? _submit : null,
            loading: _isSubmitting,
            gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
            accent: GixbeeTheme.accentBlue,
            height: 56,
            radius: 16,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _uploadedDoc(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = hiringDocumentLabel(draft.documentName, draft.documentUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: GixbeeTheme.accentGreen.withValues(alpha: 0.35)),
            color: GixbeeTheme.accentGreen.withValues(alpha: 0.08),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined,
                  color: GixbeeTheme.accentGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: context.gx.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 14, color: GixbeeTheme.accentGreen),
                        SizedBox(width: 4),
                        Text(
                          'Uploaded',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: GixbeeTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GxButton(
                label: 'Replace',
                filled: false,
                onTap: _uploadingDoc ? null : _chooseDocumentSource,
                accent: GixbeeTheme.accentBlue,
                height: 46,
                radius: 14,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GxButton(
                label: 'Remove',
                filled: false,
                onTap: _uploadingDoc ? null : _removeDocument,
                accent: cs.onSurfaceVariant,
                height: 46,
                radius: 14,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(BuildContext context, String label,
      {required bool done, String? pendingLabel}) {
    final color = done
        ? GixbeeTheme.accentGreen
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: context.gx.ink,
              ),
            ),
          ),
          Text(
            done ? '✓' : (pendingLabel ?? 'Pending'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _helper(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GxPressable(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: context.gx.ink.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border:
                    Border.all(color: context.gx.ink.withValues(alpha: 0.10)),
              ),
              child: Icon(Icons.arrow_back_rounded,
                  color: context.gx.ink, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verify Your Business',
                    style: TextStyle(
                        color: context.gx.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
                Text('Step 3 of 3',
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: GixbeeTheme.accentBlue.withValues(alpha: 0.3)),
            ),
            child: const Text('HIRING',
                style: TextStyle(
                    color: GixbeeTheme.accentBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
