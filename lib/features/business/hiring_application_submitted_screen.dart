import 'package:flutter/material.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import 'hiring_application_status_screen.dart';

class HiringApplicationSubmittedScreen extends StatelessWidget {
  final Business? business;

  const HiringApplicationSubmittedScreen({super.key, this.business});

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
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: context.gx.ink.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: context.gx.ink.withValues(alpha: 0.10)),
                    ),
                    child: Icon(Icons.close_rounded,
                        color: context.gx.ink, size: 18),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: Colors.green, size: 64),
              ),
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
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 18, color: Color(0xFFFBBF24)),
                    SizedBox(width: 8),
                    Text(
                      'UNDER REVIEW',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
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
              const Spacer(),
              GxButton(
                label: 'Go to Home',
                onTap: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
                accent: GixbeeTheme.accentBlue,
                height: 56,
                radius: 16,
                fontSize: 16,
              ),
              if (business != null) ...[
                const SizedBox(height: 10),
                GxButton(
                  label: 'View Application',
                  filled: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          HiringApplicationStatusScreen(business: business!),
                    ),
                  ),
                  accent: GixbeeTheme.accentBlue,
                  height: 52,
                  radius: 16,
                  fontSize: 15,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
