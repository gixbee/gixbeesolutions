import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../core/config/app_config.dart';
import '../../theme.dart';
import 'edit_profile_screen.dart';
import '../business/business_unit_dashboard.dart';
import '../jobs/post_job_screen.dart';
import '../activity/activity_screen.dart';
import 'profile_subscreens.dart';
import 'addresses/address_picker_bottom_sheet.dart';
import 'strikes_screen.dart';
import '../../core/theme_provider.dart';
import '../../core/main_tab_provider.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_profile_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Back from Profile: if this screen was pushed (Home avatar), pop it.
  /// If it's the Profile tab root, switching to Home — never Navigator.pop
  /// the shell (that removes MainWrapper and leaves a full black screen).
  void _onBack(BuildContext context, WidgetRef ref) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    ref.read(mainTabIndexProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final stats = ref.watch(userStatsProvider).value ?? <String, int>{};
    final bookingsCount = stats['bookings'] ?? 0;
    final savedCount = stats['saved'] ?? 0;

    final canPopRoute = Navigator.of(context).canPop();

    return PopScope(
      // Profile tab root: system back → Home, not exit app. Pushed profile: pop.
      canPop: canPopRoute,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(mainTabIndexProvider.notifier).state = 0;
      },
      child: Scaffold(
      backgroundColor: context.gx.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.gx.ink),
                    onPressed: () => _onBack(context, ref),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 88),
                child: Column(
                  children: [
                    // ── Profile Hero ──
                    userAsync.when(
                      data: (user) {
                        if (user == null) {
                          // In-tab "Session Expired" left Home / bottom nav live.
                          // MainWrapper tears the shell down; keep this tab empty.
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final name = (user.name ?? '').isNotEmpty ? user.name! : 'Gixbee User';
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: context.gx.border)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GxPressable(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const EditProfileScreen()),
                                ),
                                child: Stack(
                                  children: [
                                    GxProfileAvatar(
                                      imageUrl: user.avatar,
                                      name: name,
                                      size: 80,
                                      fontSize: 32,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: context.gx.accent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: context.gx.bg, width: 2),
                                        ),
                                        child: Icon(Icons.camera_alt,
                                            size: 14,
                                            color: context.gx.onAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.gx.ink)),
                                  SizedBox(width: 8),
                                  GxPressable(
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: context.gx.ink.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.edit_outlined, size: 14, color: context.gx.accentSoft),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.phone_outlined, size: 14, color: context.gx.accentSoft),
                                  SizedBox(width: 6),
                                  Text(user.phone, style: TextStyle(fontSize: 13, color: context.gx.ink.withValues(alpha: 0.55))),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, __) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: GxNetworkError(
                          error: e,
                          onRetry: () =>
                              ref.invalidate(currentUserProvider),
                        ),
                      ),
                    ),

                    if (userAsync.hasError || userAsync.value == null) ...[
                      // Network / session hero is the only content (no menus).
                    ] else ...[
                    // ── Stats row ──
                    Consumer(
                      builder: (context, ref, _) {
                        final statsAsync = ref.watch(userStatsProvider);
                        return statsAsync.when(
                          data: (stats) {
                            return Container(
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: context.gx.border)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        border: Border(right: BorderSide(color: context.gx.border)),
                                      ),
                                      child: Column(
                                        children: [
                                          Text('${stats['bookings'] ?? 0}',
                                              style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  color: context.gx.accentSoft)),
                                          const SizedBox(height: 2),
                                          Text('Services',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.gx.ink
                                                      .withValues(alpha: 0.55))),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        border: Border(
                                            right: BorderSide(
                                                color: context.gx.border)),
                                      ),
                                      child: Column(
                                        children: [
                                          Text('${stats['saved'] ?? 0}',
                                              style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF22C55E))),
                                          const SizedBox(height: 2),
                                          Text('Saved',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.gx.ink
                                                      .withValues(alpha: 0.55))),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        children: [
                                          Text(
                                              (stats['reviews'] ?? 0) > 0
                                                  ? '${stats['reviews']}'
                                                  : '—',
                                              style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  color: GixbeeTheme.accentGold)),
                                          const SizedBox(height: 2),
                                          Text('Reviews',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.gx.ink
                                                      .withValues(alpha: 0.55))),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    ),

                    // ── Menu Items ──
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(context, 'MY ACTIVITY'),
                          _buildMenuItem(
                            context,
                            icon: Icons.calendar_today_rounded,
                            color: context.gx.accentSoft,
                            title: 'Activity',
                            trailingText: '$bookingsCount',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ActivityScreen(
                                        initialCategory: 'services',
                                      )),
                            ),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.credit_card_outlined,
                            color: GixbeeTheme.accentGold,
                            title: 'Payment History',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PaymentHistoryScreen()),
                            ),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.favorite_border_rounded,
                            color: const Color(0xFFEC4899),
                            title: 'Saved Vendors',
                            trailingText: '$savedCount',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SavedVendorsScreen()),
                            ),
                          ),

                          _buildMenuItem(
                            context,
                            icon: Icons.location_on_outlined,
                            color: const Color(0xFF0EA5E9),
                            title: 'Saved Addresses',
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) =>
                                  const AddressPickerBottomSheet(),
                            ),
                          ),

                          _buildMenuItem(
                            context,
                            icon: Icons.gavel_rounded,
                            color: const Color(0xFFF97316),
                            title: 'Strikes & Appeals',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const StrikesScreen()),
                            ),
                          ),

                          const SizedBox(height: 6),
                          _buildSectionHeader(context, 'MY BUSINESS'),
                          _buildMenuItem(
                            context,
                            icon: Icons.storefront_outlined,
                            color: const Color(0xFF3B82F6),
                            title: 'List My Business',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BusinessUnitDashboard()),
                            ),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.work_outline_rounded,
                            color: const Color(0xFF22C55E),
                            title: 'Post a Job',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PostJobScreen()),
                            ),
                          ),

                          const SizedBox(height: 6),
                          _buildSectionHeader(context, 'SETTINGS'),
                          _buildMenuItem(
                            context,
                            icon: Icons.notifications_none_rounded,
                            color: const Color(0xFFF97316),
                            title: 'Notifications',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const NotificationSettingsScreen()),
                            ),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.language_rounded,
                            color: const Color(0xFF0EA5E9),
                            title: 'Language',
                            trailingText: 'English',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LanguageScreen()),
                            ),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.palette_outlined,
                            color: const Color(0xFF00B14F),
                            title: 'Appearance',
                            trailingText: ref.watch(themeChoiceProvider) ==
                                    AppThemeChoice.grabLight
                                ? 'Grab Green'
                                : 'Gixbee Dark',
                            onTap: () => _showThemePicker(context, ref),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.help_outline_rounded,
                            color: context.gx.accentSoft,
                            title: 'Help & Support',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const HelpSupportScreen()),
                            ),
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icons.info_outline_rounded,
                            color: context.gx.ink.withValues(alpha: 0.55),
                            title: 'About Gixbee',
                            trailingText: AppConfig.buildVersion,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AboutScreen()),
                            ),
                          ),
                          
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Builder(
                              builder: (context) {
                                final error =
                                    Theme.of(context).colorScheme.error;
                                return GxPressable(
                              onTap: () async {
                                await forceLogoutToWelcomeFromWidget(ref);
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: error.withValues(alpha: 0.08),
                                  border: Border.all(
                                      color: error.withValues(alpha: 0.13)),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.logout_rounded,
                                        color: error, size: 16),
                                    const SizedBox(width: 8),
                                    Text('Sign Out',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: error)),
                                  ],
                                ),
                              ),
                            );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    ], // logged-in only: stats + menus
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  /// Appearance picker: Gixbee Dark (default) vs Grab-style Green light.
  void _showThemePicker(BuildContext context, WidgetRef ref) {
    showGxSheet<void>(
      context,
      title: 'Appearance',
      child: Consumer(builder: (ctx, sheetRef, _) {
        final current = sheetRef.watch(themeChoiceProvider);

        Widget option(AppThemeChoice choice, String title, String sub,
            IconData icon, Color accent) {
          final selected = current == choice;
          return GxPressable(
            onTap: () {
              // Close the sheet first, then apply theme — changing ThemeMode
              // while the modal is open can leave a stale barrier / blank route.
              Navigator.pop(ctx);
              sheetRef.read(themeChoiceProvider.notifier).set(choice);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.1)
                    : ctx.gx.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: selected ? accent : ctx.gx.border,
                    width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 20,
                      color: selected
                          ? accent
                          : ctx.gx.ink.withValues(alpha: 0.35)),
                  const SizedBox(width: 12),
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: ctx.gx.ink)),
                        const SizedBox(height: 2),
                        Text(sub,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: ctx.gx.ink.withValues(alpha: 0.5))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(AppThemeChoice.grabLight, 'Grab Green',
                'Light surfaces + green accents (default)',
                Icons.light_mode_rounded, GixbeeTheme.grabGreen),
            option(AppThemeChoice.gixbeeDark, 'Gixbee Dark',
                'Deep-void look with violet accents',
                Icons.dark_mode_rounded, GixbeeTheme.accentViolet),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                'The whole app follows your choice — including login, OTP '
                'and the splash screen.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: ctx.gx.ink.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: context.gx.ink.withValues(alpha: 0.55),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    String? trailingText,
    String? trailingBadge,
    required VoidCallback onTap,
  }) {
    return GxPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.gx.ink),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55)),
              ),
            if (trailingBadge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trailingBadge,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.gx.onAccent),
                ),
              ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: context.gx.ink.withValues(alpha: 0.55), size: 20),
          ],
        ),
      ),
    );
  }
}
