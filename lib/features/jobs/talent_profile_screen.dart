import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/auth_repository.dart'; // currentUserProvider
import '../../repositories/talent_repository.dart';
import '../../shared/widgets/gx_glass_card.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_fade.dart';
import '../../theme.dart';
import 'register_pro_screen.dart';
import 'seeker_profile_wizard.dart';

/// The job seeker's talent profile — skills, experience, bio, portfolio.
/// This is what customers see when reviewing applicants.
/// Gixbee 2026 reskin: neutral header, glass profile card, ALL-CAPS bento
/// sections, skeleton loading, single gradient CTA (complete-profile).
class TalentProfileScreen extends ConsumerStatefulWidget {
  const TalentProfileScreen({super.key});

  @override
  ConsumerState<TalentProfileScreen> createState() =>
      _TalentProfileScreenState();
}

class _TalentProfileScreenState extends ConsumerState<TalentProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final profile = await ref.read(talentRepositoryProvider).getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Skills (and the bio/base rate) are managed in RegisterProScreen.
  Future<void> _openEditor() async {
    final isWorker = ref.read(currentUserProvider).value?.isWorker ?? false;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => RegisterProScreen(
                initialStep: isWorker ? 1 : 0,
                isEditingSkills: isWorker,
              )),
    );
    _fetchProfile();
  }

  /// v126 Find a Job wizard — job-seeker preferences (categories, skills,
  /// expected salary, cities). Separate from the Earn Hourly pro editor.
  Future<void> _openJobPrefs() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SeekerProfileWizard()),
    );
    _fetchProfile();
  }

  bool get _hasSkills =>
      _skillEntries.isNotEmpty ||
      (_profile?['skills'] as List?)?.isNotEmpty == true;

  /// Prefer professional skills (with ids for delete); fall back to the
  /// string `skills` list from seeker prefs.
  List<({String label, String? id})> get _skillEntries {
    final pro = _profile?['professionalSkills'] as List? ?? const [];
    if (pro.isNotEmpty) {
      return [
        for (final s in pro)
          (
            label: '${s['name'] ?? s}',
            id: s['id']?.toString(),
          ),
      ];
    }
    return [
      for (final s in (_profile?['skills'] as List? ?? const []))
        (label: '$s', id: null),
    ];
  }

  Future<void> _removeSkill(String skillId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(talentRepositoryProvider).removeSkill(skillId);
      await _fetchProfile();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          gxSnackBar('Could not remove skill: $e', type: GxSnackType.error));
    }
  }

  String get _initial {
    final name = (_profile?['fullName'] as String?)?.trim() ?? '';
    return name.isEmpty ? 'G' : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── NEUTRAL HEADER ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                GxPressable(
                  onTap: () => Navigator.pop(context),
                  child: const _RoundIconButton(
                      icon: Icons.arrow_back, semanticLabel: 'Go back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Talent Bio',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      Text(
                        'How customers see you when you apply',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: GxFade(
              child: KeyedSubtree(
                key: ValueKey(_isLoading ? 'loading' : 'data'),
                child: _isLoading
                ? _buildSkeleton()
                : RefreshIndicator(
                    onRefresh: _fetchProfile,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      children: [
                        _buildProfileCard(cs),
                        const SizedBox(height: 14),
                        _buildJobPrefsCard(cs),
                        if (!_hasSkills) ...[
                          const SizedBox(height: 14),
                          _buildCompleteCta(cs),
                        ],
                        const SizedBox(height: 24),
                        _buildSection(
                          cs,
                          icon: Icons.psychology_outlined,
                          label: 'SKILLS',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ..._skillEntries.map((e) => _SkillChip(
                                    label: e.label,
                                    onDeleted: e.id == null
                                        ? () => _openEditor()
                                        : () => _removeSkill(e.id!),
                                  )),
                              _AddSkillChip(onTap: _openEditor),
                            ],
                          ),
                        ),
                        _buildSection(
                          cs,
                          icon: Icons.work_history_outlined,
                          label: 'EXPERIENCE',
                          trailing: const _SoonPill(),
                          child: const _HintRow(
                            icon: Icons.history_rounded,
                            text:
                                'Your completed Gixbee jobs will appear here as work history.',
                          ),
                        ),
                        _buildSection(
                          cs,
                          icon: Icons.collections_outlined,
                          label: 'PORTFOLIO',
                          trailing: const _SoonPill(),
                          child: SizedBox(
                            height: 96,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: const [
                                _PortfolioPlaceholder(),
                                _PortfolioPlaceholder(),
                                _PortfolioPlaceholder(),
                              ],
                            ),
                          ),
                        ),
                        _buildSection(
                          cs,
                          icon: Icons.verified_outlined,
                          label: 'CERTIFICATIONS',
                          trailing: const _SoonPill(),
                          child: const _HintRow(
                            icon: Icons.workspace_premium_outlined,
                            text: 'Upload certificates to build trust.',
                          ),
                        ),
                        _buildSection(
                          cs,
                          icon: Icons.location_on_outlined,
                          label: 'SERVICE AREA',
                          trailing: const _SoonPill(),
                          child: const _HintRow(
                            icon: Icons.map_outlined,
                            text: 'Set the areas where you accept work.',
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildAvailabilityCard(cs),
                      ],
                    ),
                  ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── GLASS PROFILE CARD ──
  Widget _buildProfileCard(ColorScheme cs) {
    final bio = _profile?['bio'] as String?;
    return GxGlassCard(
      radius: 20,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: GixbeeTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initial,
                  style: const TextStyle(
                    color: GixbeeTheme.accentGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profile?['fullName'] ?? 'Your Name',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bio?.isNotEmpty == true
                          ? bio!
                          : 'Tap Edit to complete your profile',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GxPressable(
                onTap: _openEditor,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 14, color: GixbeeTheme.accentGreen),
                      SizedBox(width: 5),
                      Text(
                        'Edit',
                        style: TextStyle(
                          color: GixbeeTheme.accentGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProgress(cs),
        ],
      ),
    );
  }

  /// v126 Find a Job: entry card for the seeker-preferences wizard —
  /// categories, expected salary and preferred cities used for job matching.
  Widget _buildJobPrefsCard(ColorScheme cs) {
    final roles = (_profile?['preferredRoles'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final salary = _profile?['expectedSalary'];
    final subtitle = roles.isEmpty
        ? 'Set what you\'re looking for — categories, salary, cities'
        : [
            roles.take(3).join(' · '),
            if (salary != null) '₹$salary/mo',
          ].join('  ·  ');

    return GxPressable(
      onTap: _openJobPrefs,
      child: GxGlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GixbeeTheme.accentGreen.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: GixbeeTheme.accentGreen, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Job preferences',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(ColorScheme cs) {
    final progress = _hasSkills ? 0.7 : 0.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PROFILE STRENGTH · ${(progress * 100).toInt()}%',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            const Text(
              'Complete to get more jobs',
              style: TextStyle(
                color: GixbeeTheme.accentGreen,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: context.gx.ink.withValues(alpha: 0.08),
            valueColor:
                const AlwaysStoppedAnimation<Color>(GixbeeTheme.accentGreen),
          ),
        ),
      ],
    );
  }

  // ── COMPLETE-PROFILE CTA (the one gradient on this screen) ──
  Widget _buildCompleteCta(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Complete professional registration',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add your skills and rates to appear in searches.',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GxPressable(
            onTap: _openEditor,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GixbeeTheme.accentGreen,
                    GixbeeTheme.accentGreenDark,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Start Now',
                style: TextStyle(
                  color: context.gx.onAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── AVAILABILITY TOGGLE (logic unchanged) ──
  Widget _buildAvailabilityCard(ColorScheme cs) {
    const green = GixbeeTheme.accentGreen;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: green.withValues(alpha: 0.06),
        border: Border.all(color: green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: green.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.circle, size: 12, color: green),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available for Work',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  'Customers can see you in search results',
                  style:
                      TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(
            value: _profile?['jobAlertsEnabled'] ??
                _profile?['alertsEnabled'] ??
                true,
            onChanged: (val) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(talentRepositoryProvider).toggleAlerts(val);
                await _fetchProfile(); // Refresh
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                      gxSnackBar('Failed: $e', type: GxSnackType.error));
                }
              }
            },
            activeThumbColor: GixbeeTheme.accentGreen,
          ),
        ],
      ),
    );
  }

  // ── SECTION SCAFFOLD: squircle icon block + ALL-CAPS label + bento card ──
  Widget _buildSection(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    Widget? trailing,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: GixbeeTheme.accentGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  // ── SKELETON (loading) ──
  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: const [
        GxSkeleton(width: double.infinity, height: 132, radius: 20),
        SizedBox(height: 24),
        GxSkeleton(width: 140, height: 14, radius: 7),
        SizedBox(height: 12),
        GxSkeleton(width: double.infinity, height: 64, radius: 16),
        SizedBox(height: 24),
        GxSkeleton(width: 140, height: 14, radius: 7),
        SizedBox(height: 12),
        GxSkeleton(width: double.infinity, height: 64, radius: 16),
        SizedBox(height: 24),
        GxSkeleton(width: 140, height: 14, radius: 7),
        SizedBox(height: 12),
        GxSkeleton(width: double.infinity, height: 96, radius: 16),
      ],
    );
  }
}

// ─────────────────────────────────────
// SMALL PRIVATE WIDGETS
// ─────────────────────────────────────

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String? semanticLabel;
  const _RoundIconButton({required this.icon, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final container = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, size: 19),
    );
    if (semanticLabel == null) return container;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: container,
    );
  }
}

/// "SOON" pill for sections whose backing endpoints don't exist yet —
/// honest placeholder, no dead buttons.
class _SoonPill extends StatelessWidget {
  const _SoonPill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Text(
        'SOON',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HintRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final VoidCallback? onDeleted;
  const _SkillChip({required this.label, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: GixbeeTheme.accentGreen,
        ),
      ),
      onDeleted: onDeleted,
      deleteIconColor: GixbeeTheme.accentGreen,
      backgroundColor: GixbeeTheme.accentGreen.withValues(alpha: 0.10),
      side: BorderSide(
          color: GixbeeTheme.accentGreen.withValues(alpha: 0.3)),
    );
  }
}

class _AddSkillChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSkillChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GxPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: GixbeeTheme.accentGreen),
            const SizedBox(width: 4),
            Text(
              'Add Skill',
              style: TextStyle(
                color: GixbeeTheme.accentGreen,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioPlaceholder extends StatelessWidget {
  const _PortfolioPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          border:
              Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 26, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 4),
            Text(
              'Upload',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
