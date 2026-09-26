import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/glass_container.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../messages/chat_thread_screen.dart';

class CandidateProfileScreen extends StatelessWidget {
  final JobApplication application;

  const CandidateProfileScreen({super.key, required this.application});

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidate Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar & Name
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: gx.accent.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: gx.accent.withValues(alpha: 0.18),
                      child: Text(
                        application.applicantName != null ? application.applicantName![0] : 'U',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: gx.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    application.applicantName ?? 'Unknown Candidate',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(application.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getStatusColor(application.status).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      application.status.name.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(application.status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Cover Letter / Bio
            _buildSection(
              context,
              'Cover Letter',
              application.coverLetter ?? 'No cover letter provided for this application.',
            ),

            const SizedBox(height: 24),

            // Job Details
            _buildSection(
              context,
              'Applied For',
              application.jobPost.title,
              subtitle: application.jobPost.location,
            ),

            const SizedBox(height: 40),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: GxButton(
                    label: 'Resume',
                    icon: Icons.download,
                    onTap: () => _downloadResume(context),
                    filled: false,
                    accent: gx.accent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GxPressable(
                    onTap: () => _messageCandidate(context),
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gx.accentGradient),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: context.gx.onAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Message',
                            style: TextStyle(
                              color: context.gx.onAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadResume(BuildContext context) async {
    // Applicants can now attach a résumé at apply time (JobApplication.resumeUrl
    // — an /uploads/... path). Open it in the OS viewer/browser when present;
    // otherwise be honest rather than leaving a dead button.
    final raw = application.resumeUrl;
    if (raw == null || raw.isEmpty) {
      showGxSnack(
        context,
        'No résumé on file — this candidate applied without uploading one.',
        type: GxSnackType.info,
      );
      return;
    }
    // Uploads return a relative `/uploads/...` path; prefix the API base so the
    // OS browser can resolve it (mirrors edit_profile._fullUrl).
    final url = raw.startsWith('http') ? raw : '${AppConfig.baseUrl}$raw';
    final uri = Uri.tryParse(url);
    if (uri == null) {
      showGxSnack(context, 'Résumé link looks invalid',
          type: GxSnackType.error);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showGxSnack(context, 'Could not open the résumé',
          type: GxSnackType.error);
    }
  }

  void _messageCandidate(BuildContext context) {
    if (application.applicantId.isEmpty) {
      showGxSnack(context, 'Candidate contact unavailable');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          otherUserId: application.applicantId,
          otherUserName: application.applicantName ?? 'Candidate',
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: context.gx.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 12),
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                content,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Semantic status accent — matches application_tracker_screen.
  Color _getStatusColor(ApplicationStatus status) {
    return switch (status) {
      ApplicationStatus.applied => GixbeeTheme.accentGold,
      ApplicationStatus.interview => GixbeeTheme.accentBlue,
      ApplicationStatus.selected => GixbeeTheme.accentGreen,
      ApplicationStatus.rejected => GixbeeTheme.brandRed,
      ApplicationStatus.withdrawn => GixbeeTheme.textMed,
      ApplicationStatus.noShow => GixbeeTheme.brandRed,
    };
  }
}
