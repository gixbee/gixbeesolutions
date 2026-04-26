import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../onboarding/welcome_screen.dart';
import 'edit_profile_screen.dart';
import '../../repositories/profile_repository.dart';
import 'wallet_screen.dart';
import '../business/business_unit_dashboard.dart';
import '../jobs/register_pro_screen.dart';
import '../../repositories/talent_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
        ],
      ),
      body: DribbbleBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Profile Header
                userAsync.when(
                  data: (user) => Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundImage: NetworkImage(user?.avatar ??
                                '${AppConfig.avatarBaseUrl}?name=${user?.name ?? "User"}&background=6200EE&color=fff'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user?.name ?? 'User',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          user?.phone ?? user?.email ?? 'Guest',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, __) => Text('Error loading profile: $e', style: const TextStyle(color: Colors.red)),
                ),

                const SizedBox(height: 32),

                // Stats Row
                Consumer(
                  builder: (context, ref, _) {
                    final statsAsync = ref.watch(userStatsProvider);
                    return statsAsync.when(
                      data: (stats) => Row(
                        children: [
                          _ProfileStat(
                              label: 'Bookings',
                              value: '${stats['bookings']}',
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 16),
                          _ProfileStat(
                              label: 'Saved',
                              value: '${stats['saved']}',
                              color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 16),
                          _ProfileStat(
                              label: 'Reviews',
                              value: '${stats['reviews']}',
                              color: Theme.of(context).colorScheme.tertiary),
                        ],
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, __) => const Text('Error loading stats',
                          style: TextStyle(color: Colors.red)),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Menu Options
                _ProfileOption(
                  icon: Icons.person_outline,
                  label: 'Edit Profile',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EditProfileScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                _ProfileOption(
                  icon: Icons.account_balance_wallet,
                  label: 'My Wallet',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WalletScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                _ProfileOption(
                  icon: Icons.storefront_outlined,
                  label: 'My Businesses',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BusinessUnitDashboard()),
                  ),
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final talentAsync = ref.watch(talentProfileProvider);
                    return talentAsync.when(
                      data: (talent) {
                        final hasSkills = (talent['professionalSkills'] as List? ?? []).isNotEmpty;
                        return _ProfileOption(
                          icon: hasSkills ? Icons.badge_outlined : Icons.assignment_ind_outlined,
                          label: hasSkills ? 'Professional Bio' : 'Register as Pro',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterProScreen()),
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (e, __) => _ProfileOption(
                        icon: Icons.assignment_ind_outlined,
                        label: 'Register as Pro',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterProScreen()),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                userAsync.when(
                  data: (user) => _ProfileToggleOption(
                    icon: Icons.work_history_outlined,
                    label: 'Available for Work',
                    initialValue: user?.isAvailableForWork ?? true,
                    onChanged: (val) async {
                      if (user == null) return;
                      try {
                        await ref.read(profileRepositoryProvider).updateProfile(
                          userId: user.id,
                          data: {'isAvailableForWork': val},
                        );
                        // Refresh the user profile
                        ref.invalidate(currentUserProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(val ? 'You are now visible to clients for booking' : 'You are currently hidden from search')),
                          );
                        }
                      } catch (e) {
                         if (context.mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to update availability')),
                           );
                         }
                      }
                    },
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const _ProfileOption(
                    icon: Icons.notifications_none, label: 'Notifications'),
                const SizedBox(height: 16),
                const _ProfileOption(
                    icon: Icons.help_outline, label: 'Help & Support'),
                const SizedBox(height: 16),
                _ProfileOption(
                  icon: Icons.logout,
                  label: 'Log Out',
                  isData: false,
                  onTap: () async {
                    await ref.read(authRepositoryProvider).signOut();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ProfileStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                  color: color, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isData;
  final VoidCallback? onTap;

  const _ProfileOption({
    required this.icon,
    required this.label,
    this.isData = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            if (isData)
              Icon(Icons.arrow_forward_ios,
                  color: Colors.white.withValues(alpha: 0.5), size: 16),
          ],
        ),
      ),
    );
  }
}

class _ProfileToggleOption extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool initialValue;
  final ValueChanged<bool> onChanged;

  const _ProfileToggleOption({
    required this.icon,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_ProfileToggleOption> createState() => _ProfileToggleOptionState();
}

class _ProfileToggleOptionState extends State<_ProfileToggleOption> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(widget.icon, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Switch(
            value: _value,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              setState(() => _value = val);
              widget.onChanged(val);
            },
          ),
        ],
      ),
    );
  }
}
