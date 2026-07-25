import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart'; // currentUserProvider
import '../../repositories/talent_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import '../worker/go_live_screen.dart';
import 'pro_skill_provider.dart';
import 'pro_skill_taxonomy.dart';

/// "Register as Pro" / Earn Hourly — full multi-step onboarding wizard.
///
/// Step 1 Profile  — photo upload + short bio
/// Step 2 Skills   — trade categories with sub-skill checkboxes + base rate
/// Step 3 Verify   — DigiLocker (stubbed) + certificate upload
/// Step 4 Review   — summary → submit → Go Live
///
/// Gixbee 2026 design: neutral header, progress dots, glass cards, bento
/// trade cards, surgical orange (single gradient = the final CTA).
/// Public constructor unchanged — `const RegisterProScreen()` is used by
/// home_screen, profile_screen and talent_profile_screen.
class RegisterProScreen extends ConsumerStatefulWidget {
  const RegisterProScreen({super.key});

  @override
  ConsumerState<RegisterProScreen> createState() => _RegisterProScreenState();
}

class _RegisterProScreenState extends ConsumerState<RegisterProScreen> {
  int _step = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _uploadingPhoto = false;
  bool _uploadingCert = false;

  String? _approvalStatus;
  String? _photoUrl;
  final List<String> _certificates = [];
  List<dynamic> _professionalSkills = [];

  final _bioCtrl = TextEditingController();
  
  /// trade name -> specific hourly rate override
  final Map<String, TextEditingController> _tradeRateCtrls = {};

  /// trade name -> selected sub-skills
  final Map<String, Set<String>> _selected = {};
  
  /// trade name -> is expanded
  final Set<String> _expandedTrades = {};
  
  /// trade name -> skill ID (for previously saved skills so we can delete them)
  final Map<String, String> _savedSkillIds = {};

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _bioCtrl.dispose();
    for (final ctrl in _tradeRateCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String _fullUrl(String path) =>
      path.startsWith('http') ? path : '${AppConfig.baseUrl}$path';

  Future<void> _fetchProfile() async {
    try {
      final profile = await ref.read(talentRepositoryProvider).getProfile();
      // Wait for dynamic trades to load so we can map existing skills
      final trades = await ref.read(proTradesProvider.future);
      
      if (!mounted) return;
      
      setState(() {
        _professionalSkills = profile['professionalSkills'] as List? ?? [];
        _photoUrl = profile['photoUrl'] as String?;
        _certificates
          ..clear()
          ..addAll((profile['certificates'] as List? ?? []).cast<String>());
        if (profile['user'] != null) {
          _approvalStatus = profile['user']['approvalStatus'] as String?;
        }
        // Pre-fill selections + rate + bio from any existing skills.
        
        for (final s in _professionalSkills) {
          final name = '${s['name']}';
          if (s['id'] != null) {
            _savedSkillIds[name] = '${s['id']}';
          }
          final trade = trades.firstWhere(
            (t) => t.name == name,
            orElse: () => const ProTrade('', Icons.work_outline, []),
          );
          if (trade.name.isEmpty) continue;
          final bio = '${s['bio'] ?? ''}';
          // Skill tasks are stored as "about — task1, task2" (or just
          // "task1, task2" when about is empty). Only parse the tasks
          // segment so reopening the editor still matches sub-skill chips.
          final sep = bio.indexOf(' — ');
          final tasksPart = sep >= 0 ? bio.substring(sep + 3) : bio;
          final aboutPart = sep >= 0 ? bio.substring(0, sep).trim() : '';
          final subs = tasksPart
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet();
          if (subs.isNotEmpty) {
            _selected[trade.name] = subs;
            _expandedTrades.add(trade.name);
          }
          if (s['hourlyRate'] != null) {
            final parsedRate = '${s['hourlyRate']}';
            
            // Also store it specifically for this trade
            _tradeRateCtrls[trade.name] = TextEditingController(text: parsedRate);
          }
          if (_bioCtrl.text.isEmpty && aboutPart.isNotEmpty) {
            _bioCtrl.text = aboutPart;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isVerified => (_approvalStatus ?? '').toLowerCase() == 'approved';

  bool get _hasSkillSelection => _selected.values.any((set) => set.isNotEmpty);

  bool get _canAdvance {
    switch (_step) {
      case 1:
        return _hasSkillSelection;
      default:
        return true;
    }
  }

  // ── Photo + certificate uploads (image_picker → /uploads/image) ──────────
  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (x == null) return;
      setState(() => _uploadingPhoto = true);
      final bytes = await x.readAsBytes();
      final url =
          await ref.read(talentRepositoryProvider).uploadImage(bytes, x.name);
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      messenger.showSnackBar(
          gxSnackBar('Photo upload failed: $e', type: GxSnackType.error));
    }
  }

  Future<void> _addCertificate() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() => _uploadingCert = true);
      final bytes = await x.readAsBytes();
      final url =
          await ref.read(talentRepositoryProvider).uploadImage(bytes, x.name);
      if (!mounted) return;
      setState(() {
        _certificates.add(url);
        _uploadingCert = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingCert = false);
      messenger.showSnackBar(gxSnackBar('Certificate upload failed: $e',
          type: GxSnackType.error));
    }
  }

  void _toggleSub(String trade, String sub) {
    setState(() {
      final set = _selected.putIfAbsent(trade, () => <String>{});
      if (set.contains(sub)) {
        set.remove(sub);
      } else {
        set.add(sub);
      }
      if (set.isEmpty) _selected.remove(trade);
    });
  }

  // ── DigiLocker stub (credential-blocked) ─────────────────────────────────
  // TODO: needs DigiLocker API key — replace with the real OAuth consent flow.
  // The "coming soon" copy is now driven by the backend verification-status
  // stub (GET /talent/verification/status) — mirroring how the checkout UPI
  // tile renders from /payments/gateway-status — so the shell state lives in
  // one place. Falls back to local copy if the status call fails (offline).
  static const String _digiLockerFallbackMsg =
      'Government-ID verification via DigiLocker is coming soon. '
      'Verified pros rank higher and get more jobs. For now you can '
      'upload certificates below as proof.';

  Future<void> _showDigiLockerSheet() async {
    String message = _digiLockerFallbackMsg;
    try {
      final status =
          await ref.read(talentRepositoryProvider).getVerificationStatus();
      final m = status['message'];
      if (m is String && m.trim().isNotEmpty) message = m;
    } catch (_) {
      // Offline / endpoint unavailable — keep the local fallback copy.
    }
    if (!mounted) return;
    showGxSheet(
      context,
      title: 'DigiLocker verification',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
                fontSize: 13, height: 1.5, color: context.gx.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 16),
          GxButton(
            label: 'Got it',
            height: 48,
            gradient: const [GixbeeTheme.accentGold, Color(0xFFB45309)],
            accent: GixbeeTheme.accentGold,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    // Capture before save/refetch — after submit `_savedSkillIds` is always
    // non-empty, which would incorrectly skip first-time → Go Live.
    final editingExisting = _savedSkillIds.isNotEmpty ||
        (ref.read(currentUserProvider).value?.isWorker ?? false);
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(talentRepositoryProvider);
      await repo.updateProfile({
        'photoUrl': _photoUrl,
        'certificates': _certificates,
      });
      final bio = _bioCtrl.text.trim();
      
      // Delete any previously saved trades that are no longer selected
      for (final prevName in _savedSkillIds.keys) {
        final selectedSubs = _selected[prevName] ?? {};
        if (selectedSubs.isEmpty) {
          try {
            await repo.removeSkill(_savedSkillIds[prevName]!);
          } catch (e) {
            debugPrint('Failed to remove skill $prevName: $e');
          }
        }
      }

      for (final entry in _selected.entries) {
        if (entry.value.isEmpty) continue;
        
        final ctrl = _tradeRateCtrls[entry.key];
        final specificRate = (ctrl != null && ctrl.text.isNotEmpty)
            ? (double.tryParse(ctrl.text) ?? 0.0)
            : 0.0;
            
        final skillBio = bio.isEmpty
            ? entry.value.join(', ')
            : '$bio — ${entry.value.join(', ')}';
        await repo.addOrUpdateSkill(entry.key, specificRate, skillBio, {});
      }
      
      try {
        final workerRepo = ref.read(workerRepositoryProvider);
        // Go Live toggles are trade-level only ("Electrician"). Sub-skills
        // stay on the talent profile bio via addOrUpdateSkill above.
        // Instant Help dispatches by trade name, so indexing trades is enough.
        final tradeSkills = _selected.keys.toList();
        await workerRepo.registerWorker(
          skills: tradeSkills.isNotEmpty ? tradeSkills : ['General Services'],
          hourlyRate: 0.0,
          bio: bio,
        );
      } catch (e) {
        debugPrint('Worker registration failed: $e');
      }

      // Registration flips hasWorkerProfile on the backend — refetch the user
      // so user.isWorker is true IN THIS SESSION (Go Live gate + Earn Hourly
      // routing), not only after the next login.
      ref.invalidate(currentUserProvider);

      await _fetchProfile();
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (editingExisting && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        _goLive();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      messenger.showSnackBar(
          gxSnackBar('Could not save: $e', type: GxSnackType.error));
    }
  }

  void _goLive() {
    // Replace the wizard so back returns Home, not the just-finished form.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GoLiveScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(cs),
              _progress(cs),
              Expanded(
                child: _isLoading
                    ? _skeleton()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: _stepBody(cs),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _isLoading ? null : _bottomBar(cs),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          GxPressable(
            onTap: () =>
                _step == 0 ? Navigator.pop(context) : setState(() => _step--),
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
                Text('Register as Pro',
                    style: TextStyle(
                        color: context.gx.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
                Text(_stepTitle,
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          if (_isVerified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: const Text('VERIFIED',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
            ),
        ],
      ),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Step 1 of 4 — Your profile';
      case 1:
        return 'Step 2 of 4 — Your skills';
      case 2:
        return 'Step 3 of 4 — Verification';
      default:
        return 'Step 4 of 4 — Review & go live';
    }
  }

  // ── Progress dots ───────────────────────────────────────────────────────
  Widget _progress(ColorScheme cs) {
    const labels = ['Profile', 'Skills', 'Verify', 'Go Live'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (done || active)
                            ? GixbeeTheme.accentGold
                            : context.gx.ink.withValues(alpha: 0.08),
                      ),
                      alignment: Alignment.center,
                      child: done
                          ? Icon(Icons.check_rounded,
                              size: 13, color: context.gx.onAccent)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: active
                                      ? context.gx.onAccent
                                      : cs.onSurfaceVariant)),
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i],
                        style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: active
                                ? GixbeeTheme.accentGold
                                : cs.onSurfaceVariant)),
                  ],
                ),
                if (i < labels.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(
                          bottom: 16, left: 2, right: 2),
                      color: done
                          ? GixbeeTheme.accentGold
                          : context.gx.ink.withValues(alpha: 0.08),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _stepBody(ColorScheme cs) {
    switch (_step) {
      case 0:
        return _stepProfile(cs);
      case 1:
        return _stepSkills(cs);
      case 2:
        return _stepVerify(cs);
      default:
        return _stepReview(cs);
    }
  }

  // ── STEP 1: Profile ───────────────────────────────────────────────────────
  Widget _stepProfile(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GxPressable(
            onTap: _uploadingPhoto ? null : _pickPhoto,
            child: Stack(
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                    border: Border.all(
                        color:
                            GixbeeTheme.accentGold.withValues(alpha: 0.4),
                        width: 2),
                    image: (_photoUrl != null && _photoUrl!.isNotEmpty)
                        ? DecorationImage(
                            image: NetworkImage(_fullUrl(_photoUrl!)),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _uploadingPhoto
                      ? const CircularProgressIndicator(
                          color: GixbeeTheme.accentGold, strokeWidth: 2)
                      : (_photoUrl == null || _photoUrl!.isEmpty)
                          ? const Icon(Icons.person_rounded,
                              size: 48, color: GixbeeTheme.accentGold)
                          : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: GixbeeTheme.accentGold,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text('Tap to upload a profile photo',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
        const SizedBox(height: 24),
        _label(cs, 'ABOUT YOU'),
        GxTextField(
          controller: _bioCtrl,
          accent: GixbeeTheme.accentGold,
          maxLines: 4,
          hint: 'Tell customers about your experience and what you do best…',
        ),
        const SizedBox(height: 8),
        Text('This appears on your public profile when you apply for jobs.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }

  // ── STEP 2: Skills ──────────────────────────────────────────────────────
  Widget _stepSkills(ColorScheme cs) {
    final selectedFlat = <MapEntry<String, String>>[];
    for (final e in _selected.entries) {
      for (final sub in e.value) {
        selectedFlat.add(MapEntry(e.key, sub));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(cs, 'SELECT YOUR SKILLS'),
        Text(
            'Pick every task you can handle. You\'ll only be matched to jobs '
            'for the skills you select. Uncheck or tap × to remove; expand '
            'another trade to add more anytime.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        if (selectedFlat.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in selectedFlat)
                InputChip(
                  label: Text('${e.key}: ${e.value}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  onDeleted: () => _toggleSub(e.key, e.value),
                  deleteIconColor: GixbeeTheme.accentGold,
                  backgroundColor:
                      GixbeeTheme.accentGold.withValues(alpha: 0.10),
                  side: BorderSide(
                      color: GixbeeTheme.accentGold.withValues(alpha: 0.35)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ref.watch(proTradesProvider).when(
              data: (trades) => Column(
                children: trades.map((t) => _tradeCard(cs, t)).toList(),
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: GixbeeTheme.accentGold),
                ),
              ),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Failed to load skills: $err', 
                    style: TextStyle(color: cs.error)),
                ),
              ),
            ),
      ],
    );
  }

  Widget _tradeCard(ColorScheme cs, ProTrade trade) {
    final selected = _selected[trade.name] ?? <String>{};
    final count = selected.length;
    final active = count > 0;
    
    _tradeRateCtrls.putIfAbsent(trade.name, () => TextEditingController());
    final rateCtrl = _tradeRateCtrls[trade.name]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? GixbeeTheme.accentGold.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: active,
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) _expandedTrades.add(trade.name);
              else _expandedTrades.remove(trade.name);
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active
                  ? GixbeeTheme.accentGold.withValues(alpha: 0.16)
                  : context.gx.ink.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(trade.icon,
                size: 20,
                color:
                    active ? GixbeeTheme.accentGold : cs.onSurfaceVariant),
          ),
          title: Text(trade.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          subtitle: Text(active ? '$count selected' : 'Tap to choose tasks',
              style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? GixbeeTheme.accentGold
                      : cs.onSurfaceVariant)),
          children: [
            if (active)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GxTextField(
                  controller: rateCtrl,
                  label: '${trade.name} Hourly Rate (₹)',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.currency_rupee_rounded,
                  hint: 'e.g. 300',
                  onChanged: (_) {},
                ),
              ),
            if (active || _expandedTrades.contains(trade.name))
              Consumer(
                builder: (context, ref, _) {
                  final asyncSubSkills = ref.watch(subSkillsProvider(trade.name));
                  return asyncSubSkills.when(
                    data: (subSkills) {
                      if (subSkills.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No tasks found.', style: TextStyle(fontSize: 12)),
                        );
                      }
                      return Column(
                        children: subSkills.map((sub) {
                          final on = selected.contains(sub);
                          return GxPressable(
                            onTap: () => _toggleSub(trade.name, sub),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  Icon(
                                    on
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color:
                                        on ? GixbeeTheme.accentGold : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(sub,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: on ? cs.onSurface : cs.onSurfaceVariant,
                                            fontWeight:
                                                on ? FontWeight.w600 : FontWeight.w400)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: GixbeeTheme.accentGold),
                    ),
                    error: (err, stack) => Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Failed to load sub-skills: $err'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── STEP 3: Verify ──────────────────────────────────────────────────────
  Widget _stepVerify(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(cs, 'IDENTITY'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.verified_user_outlined,
                    color: GixbeeTheme.accentGold, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Verify with DigiLocker',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(
                        _isVerified
                            ? 'Your identity is verified.'
                            : 'Government-ID check. Verified pros get more jobs.',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GxButton(
          label: 'Verify with DigiLocker',
          icon: Icons.account_balance_rounded,
          filled: false,
          accent: GixbeeTheme.accentGold,
          height: 46,
          onTap: _showDigiLockerSheet,
        ),
        const SizedBox(height: 24),
        _label(cs, 'CERTIFICATES & DOCUMENTS'),
        Text(
            'Upload certificates, licenses or ID proof (images). '
            'These build trust with customers.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ..._certificates
                .asMap()
                .entries
                .map((e) => _certThumb(cs, e.key)),
            _addCertTile(cs),
          ],
        ),
      ],
    );
  }

  Widget _certThumb(ColorScheme cs, int index) {
    final url = _fullUrl(_certificates[index]);
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              image: DecorationImage(
                  image: NetworkImage(url), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GxPressable(
              onTap: () => setState(() => _certificates.removeAt(index)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addCertTile(ColorScheme cs) {
    return GxPressable(
      onTap: _uploadingCert ? null : _addCertificate,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _uploadingCert
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: GixbeeTheme.accentGold))
                : Icon(Icons.add_photo_alternate_outlined,
                    size: 26, color: GixbeeTheme.accentGold),
            const SizedBox(height: 4),
            Text(_uploadingCert ? 'Uploading' : 'Add',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── STEP 4: Review ──────────────────────────────────────────────────────
  Widget _stepReview(ColorScheme cs) {
    final selectedTrades =
        _selected.entries.where((e) => e.value.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                image: (_photoUrl != null && _photoUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(_fullUrl(_photoUrl!)),
                        fit: BoxFit.cover)
                    : null,
              ),
              alignment: Alignment.center,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? const Icon(Icons.person_rounded,
                      size: 30, color: GixbeeTheme.accentGold)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Custom rates per trade',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                      '${selectedTrades.length} trade(s) · '
                      '${_certificates.length} document(s)',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        if (_bioCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(cs, 'ABOUT'),
          Text(_bioCtrl.text.trim(),
              style:
                  TextStyle(color: cs.onSurface, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 18),
        _label(cs, 'SKILLS'),
        ...selectedTrades.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: e.value
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: GixbeeTheme.accentGold
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: GixbeeTheme.accentGold
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Text(s,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: GixbeeTheme.accentGold)),
                            ))
                        .toList(),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GixbeeTheme.accentGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: GixbeeTheme.accentGold.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: GixbeeTheme.accentGold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Submitting saves your profile and skills, then takes you '
                    'to the Go Live screen to start accepting jobs.',
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.4)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bottom bar ──────────────────────────────────────────────────────────
  Widget _bottomBar(ColorScheme cs) {
    final isLast = _step == 3;
    final enabled = _canAdvance && !_isSubmitting;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: GxButton(
                  label: 'Back',
                  filled: false,
                  accent: context.gx.ink,
                  height: 52,
                  onTap:
                      _isSubmitting ? null : () => setState(() => _step--),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: GxButton(
                // v106: Earn Hourly uses the gold accent.
                label: isLast
                    ? (_savedSkillIds.isNotEmpty
                        ? 'Save skills'
                        : 'Submit & Go Live')
                    : 'Continue',
                icon: isLast
                    ? Icons.bolt_rounded
                    : Icons.arrow_forward_rounded,
                gradient: const [GixbeeTheme.accentGold, Color(0xFFB45309)],
                accent: GixbeeTheme.accentGold,
                height: 52,
                loading: _isSubmitting,
                onTap: enabled
                    ? (isLast ? _submit : () => setState(() => _step++))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────
  Widget _label(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant)),
    );
  }

  Widget _skeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: const [
        Center(child: GxSkeleton(width: 104, height: 104, radius: 52)),
        SizedBox(height: 24),
        GxSkeleton(width: 120, height: 14, radius: 7),
        SizedBox(height: 10),
        GxSkeleton(width: double.infinity, height: 96, radius: 14),
        SizedBox(height: 20),
        GxSkeleton(width: double.infinity, height: 64, radius: 16),
        SizedBox(height: 12),
        GxSkeleton(width: double.infinity, height: 64, radius: 16),
      ],
    );
  }
}
