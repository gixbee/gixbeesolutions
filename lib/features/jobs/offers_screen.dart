import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Special Offers', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.gx.ink),
        titleTextStyle: TextStyle(color: context.gx.ink, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: DribbbleBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildModernOfferCard(
                context,
                'Summer Special',
                'Get 20% off on all AC services this week.',
                'SUMMER20',
                Icons.ac_unit_rounded,
                GixbeeTheme.accentBlue,
              ),
              const SizedBox(height: 16),
              _buildModernOfferCard(
                context,
                'Referral Bonus',
                'Invite a friend and get ₹500 credit.',
                'GIXFRIEND',
                Icons.people_rounded,
                colorScheme.secondary,
              ),
              const SizedBox(height: 16),
              _buildModernOfferCard(
                context,
                'New Professional',
                'First booking discount for new users.',
                'FIRSTPRO',
                Icons.stars_rounded,
                colorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernOfferCard(
    BuildContext context,
    String title,
    String desc,
    String code,
    IconData icon,
    Color accentColor,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.gx.ink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.gx.ink.withValues(alpha: 0.24)),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: context.gx.ink,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: context.gx.ink,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(
              color: context.gx.ink.withValues(alpha: 0.6),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          GxButton(
            label: 'Claim Offer',
            onTap: () => _claimOffer(context, code),
            gradient: [accentColor, accentColor],
            accent: accentColor,
            height: 48,
            radius: 12,
          ),
        ],
      ),
    );
  }

  /// Copies the promo code to the clipboard and confirms via a glass toast —
  /// the same dependency-free pattern Today's Offers uses on the home screen
  /// (`home_sections.dart` `_claim`). No backend offers endpoint exists yet, so
  /// claiming = "code in hand, show it at the store/checkout".
  Future<void> _claimOffer(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) {
      showGxSnack(context, 'Code $code copied — apply it at checkout',
          type: GxSnackType.success);
    }
  }
}

