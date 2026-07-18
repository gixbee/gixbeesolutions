import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/support_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Contact support + my tickets. Any issue that isn't tied to a live booking
/// goes through here (booking problems use the in-job Report flow). Tickets
/// land in the admin portal's Support inbox; the reply shows up under the
/// ticket and arrives as a push notification.
class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  ConsumerState<SupportTicketsScreen> createState() =>
      _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends ConsumerState<SupportTicketsScreen> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tickets = await ref.read(supportRepositoryProvider).myTickets();
      if (mounted) {
        setState(() {
          _tickets = tickets;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Tickets load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewTicket() async {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    var submitting = false;

    await showGxSheet<void>(
      context,
      title: 'Contact support',
      child: StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> submit() async {
            final subject = subjectCtrl.text.trim();
            final message = messageCtrl.text.trim();
            if (subject.isEmpty || message.isEmpty) {
              showGxSnack(ctx, 'Please fill in both fields',
                  type: GxSnackType.error);
              return;
            }
            setSheet(() => submitting = true);
            try {
              await ref
                  .read(supportRepositoryProvider)
                  .createTicket(subject: subject, message: message);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                showGxSnack(context,
                    'Ticket submitted — our team will reply soon.',
                    type: GxSnackType.success);
                _load();
              }
            } catch (e) {
              if (ctx.mounted) {
                setSheet(() => submitting = false);
                showGxSnack(ctx, 'Could not submit: $e',
                    type: GxSnackType.error);
              }
            }
          }

          InputDecoration dec(String hint) => InputDecoration(
                hintText: hint,
                hintStyle:
                    TextStyle(color: context.gx.ink.withValues(alpha: 0.3)),
                filled: true,
                fillColor: context.gx.card2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.gx.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.gx.border),
                ),
              );

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: subjectCtrl,
                maxLength: 120,
                style: TextStyle(color: context.gx.ink, fontSize: 14),
                decoration: dec('Subject — what\'s it about?'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageCtrl,
                maxLines: 5,
                style: TextStyle(color: context.gx.ink, fontSize: 14),
                decoration: dec('Describe the issue…'),
              ),
              const SizedBox(height: 16),
              GxButton(
                label: submitting ? 'Submitting…' : 'Submit ticket',
                onTap: submitting ? null : submit,
              ),
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );

    subjectCtrl.dispose();
    messageCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Support tickets',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _tickets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.support_agent_rounded,
                                    size: 44,
                                    color:
                                        context.gx.ink.withValues(alpha: 0.25)),
                                const SizedBox(height: 12),
                                Text('No tickets yet',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: context.gx.ink
                                            .withValues(alpha: 0.5))),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              itemCount: _tickets.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) =>
                                  _ticketCard(_tickets[i]),
                            ),
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: GxButton(
                  label: 'Contact support',
                  icon: Icons.support_agent_rounded,
                  onTap: _openNewTicket,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final resolved = t['status'] == 'RESOLVED';
    final reply = t['reply'] as String?;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${t['subject'] ?? ''}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.gx.ink)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (resolved
                          ? GixbeeTheme.accentGreen
                          : GixbeeTheme.accentGold)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(resolved ? 'Resolved' : 'Open',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: resolved
                            ? GixbeeTheme.accentGreen
                            : GixbeeTheme.accentGold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${t['message'] ?? ''}',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: context.gx.ink.withValues(alpha: 0.6))),
          if (reply != null && reply.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              width: double.infinity,
              decoration: BoxDecoration(
                color: GixbeeTheme.accentGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GIXBEE SUPPORT',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: GixbeeTheme.accentGreen)),
                  const SizedBox(height: 4),
                  Text(reply,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.5, color: context.gx.ink)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
