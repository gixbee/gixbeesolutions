import 'package:flutter/material.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import 'business_unit_dashboard.dart';
import 'hiring_business_verification_screen.dart';
import 'hiring_listing.dart';

class HiringApplicationStatusScreen extends StatelessWidget {
  final Business business;

  const HiringApplicationStatusScreen({super.key, required this.business});

  String get _status => business.status.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GxPressable(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: context.gx.ink.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: context.gx.ink.withValues(alpha: 0.10)),
                    ),
                    child: Icon(Icons.arrow_back_rounded,
                        color: context.gx.ink, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12, bottom: 16),
                  child: switch (_status) {
                    'VERIFIED' => _verified(context),
                    'NEEDS_CHANGES' => _needsChanges(context),
                    'REJECTED' => _rejected(context),
                    _ => _underReview(context),
                  },
                ),
              ),
              ..._actions(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (_status) {
      case 'VERIFIED':
        return [
          GxButton(
            label: 'Open Hiring Dashboard',
            onTap: () => _openDashboard(context),
            gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
            accent: GixbeeTheme.accentBlue,
            height: 56,
            radius: 16,
            fontSize: 16,
          ),
        ];
      case 'NEEDS_CHANGES':
        return [
          GxButton(
            label: 'Update & Resubmit',
            onTap: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HiringBusinessVerificationScreen(
                  draft: HiringListingDraft.fromBusiness(business),
                ),
              ),
            ),
            gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
            accent: GixbeeTheme.accentBlue,
            height: 56,
            radius: 16,
            fontSize: 16,
          ),
        ];
      default:
        return [
          GxButton(
            label: 'Go to Home',
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
            accent: GixbeeTheme.accentBlue,
            height: 56,
            radius: 16,
            fontSize: 16,
          ),
        ];
    }
  }

  void _openDashboard(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BusinessUnitDashboard()),
      (route) => route.isFirst,
    );
  }

  Widget _underReview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _heroIcon(Icons.hourglass_top_rounded, const Color(0xFFFBBF24)),
        const SizedBox(height: 22),
        Text(
          'Application Submitted',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: context.gx.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We\'re reviewing your business details.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        _statusCard(
          'UNDER REVIEW',
          const Color(0xFFFBBF24),
          const Color(0xFFB45309),
          Icons.schedule_rounded,
        ),
        const SizedBox(height: 16),
        Text(
          'We\'ll notify you when verification is complete.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.85),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _needsChanges(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final note = hiringReviewNote(business.hiringProfile);
    return Column(
      children: [
        _heroIcon(Icons.edit_note_rounded, const Color(0xFFF59E0B)),
        const SizedBox(height: 22),
        Text(
          'Verification Needs Changes',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: context.gx.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please update the highlighted details and resubmit.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        _statusCard(
          'NEEDS CHANGES',
          const Color(0xFFF59E0B),
          const Color(0xFFB45309),
          Icons.priority_high_rounded,
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Requested changes',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: context.gx.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                note.isEmpty
                    ? 'Business registration document is unclear.'
                    : note,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: context.gx.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _verified(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _heroIcon(Icons.verified_rounded, GixbeeTheme.accentGreen),
        const SizedBox(height: 22),
        Text(
          'Business Verified ✓',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: context.gx.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your business is now verified. You can start posting jobs.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        _statusCard(
          'VERIFIED',
          GixbeeTheme.accentGreen,
          const Color(0xFF166534),
          Icons.verified_rounded,
        ),
      ],
    );
  }

  Widget _rejected(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final note = hiringReviewNote(business.hiringProfile);
    return Column(
      children: [
        _heroIcon(Icons.cancel_outlined, Colors.redAccent),
        const SizedBox(height: 22),
        Text(
          'Application Rejected',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: context.gx.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          note.isEmpty
              ? 'This business was not verified. Contact support if you need help.'
              : note,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        _statusCard(
          'REJECTED',
          Colors.redAccent,
          const Color(0xFF991B1B),
          Icons.cancel_outlined,
        ),
      ],
    );
  }

  Widget _heroIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Icon(icon, color: color, size: 64),
    );
  }

  Widget _statusCard(
      String label, Color color, Color textColor, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
