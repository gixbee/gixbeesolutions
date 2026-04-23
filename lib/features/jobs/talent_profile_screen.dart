import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/talent_repository.dart';
import 'register_pro_screen.dart';

/// The job seeker's talent profile — skills, experience, bio, portfolio.
/// This is what customers see when reviewing applicants.
class TalentProfileScreen extends ConsumerStatefulWidget {
  const TalentProfileScreen({super.key});

  @override
  ConsumerState<TalentProfileScreen> createState() => _TalentProfileScreenState();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── HEADER ──
              Text(
                'Talent Bio',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'This is how customers see you when you apply',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),

              const SizedBox(height: 24),

              // ── PROFILE CARD ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF54A0FF).withValues(alpha: 0.08),
                      cs.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF54A0FF).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    // Avatar + name
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor:
                              const Color(0xFF54A0FF).withValues(alpha: 0.15),
                          child: const Icon(Icons.person,
                              size: 32, color: Color(0xFF54A0FF)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _profile?['fullName'] ?? 'Your Name',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                _profile?['bio']?.isNotEmpty == true
                                    ? _profile!['bio']
                                    : 'Tap to complete your profile',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, color: cs.primary),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Completion progress
                    _ProgressSection(
                      progress: _profile?['skills']?.isNotEmpty == true ? 0.7 : 0.3,
                      cs: cs,
                    ),
                  ],
                ),
              ),

              if (_profile?['skills']?.isEmpty == true) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Complete Professional Registration',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Add your skills and rates to appear in searches.',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterProScreen()),
                          );
                        },
                        child: const Text('Start Now'),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ── SECTIONS ──
              _buildSection(
                context,
                icon: Icons.psychology_outlined,
                title: 'Skills',
                subtitle: 'What are you good at?',
                trailing: _buildAddButton(context),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...(_profile?['skills'] as List? ?? []).map((s) => _SkillChip(label: s, level: 'Expert')),
                    _AddSkillChip(onTap: () {}),
                  ],
                ),
              ),

              _buildSection(
                context,
                icon: Icons.work_history_outlined,
                title: 'Experience',
                subtitle: 'Your work history',
                trailing: _buildAddButton(context),
                child: const Column(
                  children: [
                    _ExperienceItem(
                      role: 'Freelance Plumber',
                      place: 'Self-employed',
                      period: '2020 – Present',
                      description:
                          'Residential plumbing repairs, pipe installations, and bathroom fittings across Kochi.',
                    ),
                    _EmptyExperienceHint(),
                  ],
                ),
              ),

              _buildSection(
                context,
                icon: Icons.collections_outlined,
                title: 'Portfolio',
                subtitle: 'Photos of past work',
                trailing: _buildAddButton(context),
                child: SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _PortfolioPlaceholder(onTap: () {}),
                      _PortfolioPlaceholder(onTap: () {}),
                      _PortfolioPlaceholder(onTap: () {}),
                    ],
                  ),
                ),
              ),

              _buildSection(
                context,
                icon: Icons.verified_outlined,
                title: 'Certifications',
                subtitle: 'Licenses & training',
                trailing: _buildAddButton(context),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 20, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Upload certificates to build trust',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              _buildSection(
                context,
                icon: Icons.location_on_outlined,
                title: 'Service Area',
                subtitle: 'Where you work',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const _AreaChip(label: 'Kochi'),
                    const _AreaChip(label: 'Ernakulam'),
                    const _AreaChip(label: 'Aluva'),
                    ActionChip(
                      avatar: Icon(Icons.add, size: 16, color: cs.primary),
                      label: const Text('Add Area',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── AVAILABILITY TOGGLE ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.green.withValues(alpha: 0.06),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green.withValues(alpha: 0.12),
                      ),
                      child: const Icon(Icons.circle,
                          size: 12, color: Colors.green),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available for Work',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Customers can see you in search results',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _profile?['alertsEnabled'] ?? true,
                      onChanged: (val) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref.read(talentRepositoryProvider).toggleAlerts(val);
                          await _fetchProfile(); // Refresh
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                          }
                        }
                      },
                      activeThumbColor: Colors.green,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(subtitle,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.add_circle_outline,
          size: 20, color: Theme.of(context).colorScheme.primary),
      onPressed: () {},
      constraints: const BoxConstraints(),
      padding: EdgeInsets.zero,
    );
  }
}

// ─────────────────────────────────────
// PROGRESS SECTION
// ─────────────────────────────────────
class _ProgressSection extends StatelessWidget {
  final double progress;
  final ColorScheme cs;
  const _ProgressSection({required this.progress, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Profile ${(progress * 100).toInt()}% complete',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              'Complete to get more jobs',
              style:
                  TextStyle(color: cs.primary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF54A0FF)),
          ),
        ),
      ],
    );
  }
}

// SKILL CHIP
class _SkillChip extends StatelessWidget {
  final String label;
  final String level;
  const _SkillChip({required this.label, required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF54A0FF).withValues(alpha: 0.08),
        border: Border.all(
            color: const Color(0xFF54A0FF).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(level,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10)),
        ],
      ),
    );
  }
}

class _AddSkillChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSkillChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: cs.primary),
            const SizedBox(width: 4),
            Text('Add Skill',
                style: TextStyle(color: cs.primary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// EXPERIENCE ITEM
class _ExperienceItem extends StatelessWidget {
  final String role;
  final String place;
  final String period;
  final String description;
  const _ExperienceItem({
    required this.role,
    required this.place,
    required this.period,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        border:
            Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(role,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14))),
              Text(period,
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 11)),
            ],
          ),
          Text(place,
              style: TextStyle(color: cs.primary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(description,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4)),
        ],
      ),
    );
  }
}

class _EmptyExperienceHint extends StatelessWidget {
  const _EmptyExperienceHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.2),
            style: BorderStyle.solid),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text('Add more experience',
              style: TextStyle(color: cs.primary, fontSize: 12)),
        ],
      ),
    );
  }
}

// PORTFOLIO
class _PortfolioPlaceholder extends StatelessWidget {
  final VoidCallback onTap;
  const _PortfolioPlaceholder({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 28, color: cs.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 4),
              Text('Upload',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// AREA CHIP
class _AreaChip extends StatelessWidget {
  final String label;
  const _AreaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: () {},
    );
  }
}

