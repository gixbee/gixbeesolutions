import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../repositories/favourites_repository.dart';
import '../../shared/models/worker.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../search/worker_detail_screen.dart';
import 'support_tickets_screen.dart';

// v106 purple-primary accent migration (2026-06-15): orange brand accents
// swapped to the violet/purple family — language-select check, Payment
// History gradient header + card icons, Pending chip (gold), earnings stat
// cards + amount. Logic/structure unchanged. The About "gixbee" wordmark
// intentionally stays orange (scheme.primary) per the v106 wordmark rule.

// ── Shared state ────────────────────────────────────────────────────────────

/// Selected app language (display only for now; persisted in memory).
final languageProvider = StateProvider<String>((ref) => 'English');

/// Notification preference toggles.
final notificationPrefsProvider =
    StateProvider<Map<String, bool>>((ref) => {
          'Booking confirmations': true,
          'Payment alerts': true,
          'Service status updates': true,
          'Offers & deals': false,
          'Gixbee news & updates': false,
        });

// ── Language picker ──────────────────────────────────────────────────────────

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  static const _languages = [
    ('English', 'English'),
    ('हिन्दी', 'Hindi'),
    ('മലയാളം', 'Malayalam'),
    ('ಕನ್ನಡ', 'Kannada'),
    ('தமிழ்', 'Tamil'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(languageProvider);

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GxPressable(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back_rounded, color: context.gx.ink, size: 20),
                        SizedBox(width: 4),
                        Text('Back', style: TextStyle(fontSize: 14, color: context.gx.ink, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Language',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  SizedBox(width: 44), // balance back button
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: context.gx.border)),
                    ),
                    child: Text(
                      'Select your preferred language for the app',
                      style: TextStyle(fontSize: 13, color: context.gx.ink.withValues(alpha: 0.55)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._languages.map((lang) {
                    final native = lang.$1;
                    final english = lang.$2;
                    final isSel = selected == english;

                    return GxPressable(
                      onTap: () {
                        ref.read(languageProvider.notifier).state = english;
                        showGxSnack(context, 'Language set to $english', type: GxSnackType.success);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: context.gx.ink.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: isSel ? Border.all(color: context.gx.accentSoft, width: 1.5) : Border.all(color: Colors.transparent, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    native,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.gx.ink),
                                  ),
                                  if (english != native) ...[
                                    SizedBox(height: 2),
                                    Text(
                                      english,
                                      style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              isSel ? Icons.check_circle_rounded : Icons.circle_outlined,
                              color: isSel ? context.gx.accentSoft : context.gx.ink.withValues(alpha: 0.55),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification settings ────────────────────────────────────────────────────

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GxPressable(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back_rounded, color: context.gx.ink, size: 20),
                        SizedBox(width: 4),
                        Text('Back', style: TextStyle(fontSize: 14, color: context.gx.ink, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Notifications',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  SizedBox(width: 44),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      'BOOKING ALERTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.55),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...['Booking confirmations', 'Payment alerts', 'Service status updates'].map((key) {
                    final val = prefs[key] ?? false;
                    return _buildToggle(context, ref, key, val);
                  }),
                  
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'PROMOTIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.55),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...['Offers & deals', 'Gixbee news & updates'].map((key) {
                    final val = prefs[key] ?? false;
                    return _buildToggle(context, ref, key, val);
                  }),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.06),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.13)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'We never send spam. You can turn off any notification type anytime.',
                            style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55), height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(BuildContext context, WidgetRef ref, String key, bool value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.gx.ink.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.gx.ink)),
          Switch(
            value: value,
            activeThumbColor: context.gx.accentSoft,
            inactiveTrackColor: context.gx.border,
            inactiveThumbColor: context.gx.ink.withValues(alpha: 0.55),
            onChanged: (val) {
              final prefs = ref.read(notificationPrefsProvider);
              final next = Map<String, bool>.from(prefs)..[key] = val;
              ref.read(notificationPrefsProvider.notifier).state = next;
            },
          ),
        ],
      ),
    );
  }
}

// ── Help & Support ──────────────────────────────────────────────────────────

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GxPressable(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back_rounded, color: context.gx.ink, size: 20),
                        SizedBox(width: 4),
                        Text('Back', style: TextStyle(fontSize: 14, color: context.gx.ink, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Help & Support',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  SizedBox(width: 44),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // ── Quick Help ──
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GxPressable(
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connecting to chat support...'))),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: context.gx.accentSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, color: context.gx.onAccent, size: 24),
                                  SizedBox(height: 6),
                                  Text('Live Chat', style: TextStyle(color: context.gx.onAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: GxPressable(
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calling +91 1800 123 4567...'))),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.phone_outlined, color: context.gx.onAccent, size: 24),
                                  SizedBox(height: 6),
                                  Text('Call Us', style: TextStyle(color: context.gx.onAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: context.gx.border),
                  ),

                  // ── FAQ ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'FREQUENTLY ASKED QUESTIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.gx.ink.withValues(alpha: 0.55),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),

                  _buildFaqItem(context, 'How do I cancel a booking?', 'You can cancel a booking from the My Bookings section. Please note our cancellation policy.'),
                  _buildFaqItem(context, 'When will I get my refund?', 'Refunds are processed within 5-7 business days to your original payment method.'),
                  _buildFaqItem(context, 'How do I contact a vendor?', 'You can message or call a vendor directly from their profile or booking details page.'),

                  SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: context.gx.border),
                  ),

                  // ── Contact ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Text(
                      'Still need help?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: context.gx.ink.withValues(alpha: 0.55)),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GxPressable(
                      // Real support channel: file a ticket → admin portal
                      // Support inbox → reply shows here + push notification.
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SupportTicketsScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: context.gx.ink.withValues(alpha: 0.05),
                          border: Border.all(color: context.gx.border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.support_agent_rounded, color: context.gx.accentSoft, size: 16),
                            SizedBox(width: 8),
                            Text('Contact Support · My Tickets', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.gx.ink.withValues(alpha: 0.55))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem(BuildContext context, String question, String answer) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.gx.ink.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(question, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.gx.ink)),
        iconColor: context.gx.accentSoft,
        collapsedIconColor: context.gx.ink.withValues(alpha: 0.55),
        shape: Border(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(answer, style: TextStyle(fontSize: 13, color: context.gx.ink.withValues(alpha: 0.55), height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ── Saved vendors ────────────────────────────────────────────────────────────

/// The signed-in user's saved (favourited) pros, resolved to full [Worker]
/// objects. Composes the favourites endpoint (ids only) with a per-id worker
/// fetch; ids that no longer resolve (deleted/hidden pros) are skipped rather
/// than failing the whole list. autoDispose so it re-fetches each visit.
final savedWorkersProvider =
    FutureProvider.autoDispose<List<Worker>>((ref) async {
  final ids = await ref.watch(favouritesRepositoryProvider).getMyFavouriteIds();
  if (ids.isEmpty) return <Worker>[];
  final repo = ref.watch(workerRepositoryProvider);
  final results = await Future.wait(ids.map((id) async {
    try {
      return await repo.getWorkerById(id);
    } catch (_) {
      return null; // skip workers that no longer resolve
    }
  }));
  return results.whereType<Worker>().toList();
});

/// Saved pros — the destination for the worker_detail / worker_list favourite
/// heart. Class name + const ctor kept (profile_screen menu row binds it).
class SavedVendorsScreen extends ConsumerWidget {
  const SavedVendorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(savedWorkersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Pros')),
      body: savedAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          itemCount: 6,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: GxSkeleton(width: double.infinity, height: 80, radius: 16),
          ),
        ),
        error: (e, _) => const GxEmptyState(
          icon: Icons.bookmark_border_rounded,
          title: 'Couldn\'t load saved pros',
          message: 'Pull down to refresh, or try again in a moment.',
        ),
        data: (workers) {
          if (workers.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(savedWorkersProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                      height: MediaQuery.of(context).size.height * 0.16),
                  const GxEmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: 'No saved pros yet',
                    message:
                        'Tap the heart on any pro to save them here for quick rebooking.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(savedWorkersProvider.future),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: workers.length,
              itemBuilder: (context, i) =>
                  _SavedWorkerCard(worker: workers[i]),
            ),
          );
        },
      ),
    );
  }
}

/// Compact saved-pro row — avatar, name/title, rating + rate. Taps through to
/// the worker detail screen (instant mode) for re-booking.
class _SavedWorkerCard extends StatelessWidget {
  final Worker worker;
  const _SavedWorkerCard({required this.worker});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GxPressable(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WorkerDetailScreen(worker: worker, isInstant: true),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.gx.card2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gx.ink.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: NetworkImage(worker.imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.gx.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 2),
                    Text(
                      worker.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 3),
                        Text(
                          '${worker.rating.toStringAsFixed(1)} (${worker.reviewCount})',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.gx.ink),
                        ),
                        SizedBox(width: 10),
                        Text(
                          '₹${worker.hourlyRate.toInt()}/hr',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: context.gx.accent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: context.gx.ink.withValues(alpha: 0.35), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Payment history ──────────────────────────────────────────────────────────

/// Worker earnings summary for the Earnings tab — same
/// `GET /workers/me/dashboard` payload the Go Live screen uses.
final _earningsDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(workerRepositoryProvider).getGoLiveDashboard();
});

String _rupees(dynamic v) {
  final n = (v is num) ? v : num.tryParse('$v') ?? 0;
  return '₹${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
}

/// Payment history: money out (booking payments) and — for Pros — money in
/// (Go Live earnings, surfaced from the worker dashboard).
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final isWorker = user?.isWorker ?? false;

    return DefaultTabController(
      length: isWorker ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Payment History',
              style: TextStyle(color: context.gx.onAccent, fontWeight: FontWeight.w800)),
          iconTheme: IconThemeData(color: context.gx.onAccent),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: context.gx.accentGradient),
            ),
          ),
          bottom: isWorker
              ? TabBar(
                  indicatorColor: context.gx.onAccent,
                  indicatorWeight: 3,
                  labelColor: context.gx.onAccent,
                  unselectedLabelColor: context.gx.onAccent.withValues(alpha: 0.7),
                  labelStyle:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: const [Tab(text: 'Payments'), Tab(text: 'Earnings')],
                )
              : null,
        ),
        body: isWorker
            ? const TabBarView(
                children: [_PaymentsTab(), _EarningsTab()],
              )
            : const _PaymentsTab(),
      ),
    );
  }
}

/// Money out — payments for the user's bookings (customer side).
class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bookingsAsync = ref.watch(myBookingsProvider);
    final user = ref.watch(currentUserProvider).value;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myBookingsProvider);
        await ref.read(myBookingsProvider.future);
      },
      child: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text('Could not load payments. Pull to retry.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        data: (bookings) {
          // Customer-side bookings only; worker-side jobs are Earnings.
          final uid = user?.id;
          final mine = bookings.whereType<Map>().where((b) {
            final opId = b['operator'] is Map ? b['operator']['id'] : b['operator'];
            return uid == null || opId == null || opId != uid;
          }).toList()
            ..sort((a, b) => ('${b['createdAt'] ?? b['scheduledAt'] ?? ''}')
                .compareTo('${a['createdAt'] ?? a['scheduledAt'] ?? ''}'));

          if (mine.isEmpty) return _emptyState(scheme);

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: mine.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                _paymentCard(context, scheme, Map<String, dynamic>.from(mine[i])),
          );
        },
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        GxEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No payments yet',
          message:
              'Payments for your bookings will appear here. Wallet top-ups are shown in My Wallet.',
        ),
      ],
    );
  }

  Widget _paymentCard(BuildContext context, ColorScheme scheme, Map<String, dynamic> b) {
    final status = (b['status'] ?? '').toString().toUpperCase();
    final isPaid = b['isPaid'] == true;
    final method = (b['paymentMethod'] ?? 'WALLET').toString().toUpperCase();
    final worker = b['operator'] is Map ? b['operator'] as Map : const {};
    final when = DateTime.tryParse('${b['createdAt'] ?? b['scheduledAt'] ?? ''}');

    final (chipLabel, chipColor) = switch ((status, isPaid)) {
      ('CANCELLED', _) => ('Refunded', scheme.onSurfaceVariant),
      (_, true) => ('Paid · $method', Colors.green),
      _ => ('Pending', GixbeeTheme.accentGold),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: context.gx.accentGradient),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((b['skill'] ?? b['serviceName'] ?? 'Service booking').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (worker['name'] != null) '${worker['name']}',
                    if (when != null) DateFormat('MMM d, yyyy').format(when),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_rupees(b['totalAmount'] ?? b['amount']),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface)),
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(chipLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: chipColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Money in — Go Live earnings for Pros (worker dashboard payload).
class _EarningsTab extends ConsumerWidget {
  const _EarningsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dashAsync = ref.watch(_earningsDashboardProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_earningsDashboardProvider);
        await ref.read(_earningsDashboardProvider.future);
      },
      child: dashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ListView(
          children: [
            const SizedBox(height: 100),
            const GxEmptyState(
              icon: Icons.payments_outlined,
              title: 'No earnings yet',
              message:
                  'Complete your Pro profile and go live to start earning. Completed jobs appear here.',
            ),
          ],
        ),
        data: (dash) {
          final e =
              Map<String, dynamic>.from(dash['earnings'] as Map? ?? const {});
          final recent = (e['recent'] as List? ?? const [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _stat(context, scheme, 'Today', _rupees(e['today'])),
                  const SizedBox(width: 10),
                  _stat(context, scheme, 'This week', _rupees(e['thisWeek'])),
                  const SizedBox(width: 10),
                  _stat(context, scheme, 'Total', _rupees(e['total'])),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('${e['jobsCompleted'] ?? 0} jobs completed',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(height: 16),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('Completed jobs will be listed here.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                )
              else ...[
                Text('COMPLETED JOBS',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    )),
                const SizedBox(height: 8),
                ...recent.map((j) {
                  final when = DateTime.tryParse('${j['completedAt'] ?? ''}');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: context.gx.accentGradient),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(Icons.check_rounded,
                              size: 17, color: context.gx.onAccent),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((j['skill'] ?? 'Service').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  )),
                              Text(
                                [
                                  (j['customerName'] ?? 'Customer').toString(),
                                  if (when != null)
                                    DateFormat('MMM d').format(when),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(_rupees(j['amount']),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: context.gx.accentSoft,
                            )),
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, ColorScheme scheme, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: context.gx.accentSoft.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: context.gx.accentSoft.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface)),
            const SizedBox(height: 2),
            Text(label,
                style:
                    TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ── Help / FAQ ───────────────────────────────────────────────────────────────

class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  static const _faqs = [
    (
      'How do I book a service?',
      'Open Home, choose Plan an Event or Instant Help, pick a service and a '
          'provider, set your location and time, then confirm. You can chat with '
          'the provider before and after booking.'
    ),
    (
      'How does Go Live work?',
      'If you have a Pro profile, tap the green Go Live button in the center of '
          'the bottom bar to appear on the map and receive instant job requests. '
          'Toggle off any time to stop receiving jobs.'
    ),
    (
      'How are payments handled?',
      'You can pay from your Gixbee wallet, UPI/PhonePe, bank transfer, or cash. '
          'Choose a method at checkout. Refunds for cancellations go back to your '
          'wallet automatically.'
    ),
    (
      'How do I cancel a booking?',
      'Open the booking, tap Cancel, choose a reason and confirm. Any captured '
          'payment is refunded to your wallet.'
    ),
    (
      'Is my data safe?',
      'Yes. Identity verification is handled via government-backed DigiLocker and '
          'Gixbee never stores your Aadhaar number.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: ListView(
        children: [
          for (final faq in _faqs)
            ExpansionTile(
              title: Text(faq.$1,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(faq.$2,
                      style: TextStyle(
                          height: 1.6,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Center(
            child: Text('Still need help? gixbeesolutions@gmail.com',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── About ────────────────────────────────────────────────────────────────────

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About Gixbee')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Text('gixbee',
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary)),
            const SizedBox(height: 4),
            Text('The Skill Intelligence Network',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            Text(
              'Gixbee is an intent-based platform for event booking, instant help, '
              'gig work, job discovery and vendor management — one app, unlimited '
              'opportunities.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6, color: scheme.onSurface),
            ),
            const SizedBox(height: 28),
            _row(scheme, 'Version', AppConfig.buildVersion),
            _row(scheme, 'Region', 'Kerala & Tamil Nadu'),
            _row(scheme, 'Support', 'gixbeesolutions@gmail.com'),
            const Spacer(),
            Text('© 2026 Gixbee',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _row(ColorScheme scheme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(color: scheme.onSurfaceVariant)),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
