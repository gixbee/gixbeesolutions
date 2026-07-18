import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../repositories/auth_repository.dart'; // dioProvider
import '../../repositories/cities_repository.dart'; // currentCityProvider
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../booking/book_services_split_screen.dart';
import '../booking/instant_request_screen.dart';

/// Secondary home sections from the mockup:
/// quick-service tiles (horizontal scroll), Popular Events, Today's Deals.

void _push(BuildContext context, Widget screen) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

Widget _sectionTitle(BuildContext context, String title, {String? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  )),
        ),
        if (trailing != null)
          Text(trailing,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.gx.accentSoft)),
      ],
    ),
  );
}

// ── Quick services (horizontal tile scroll) ───────────────────────────────
class QuickServicesStrip extends StatelessWidget {
  const QuickServicesStrip({super.key});

  // Same labels as the Instant Help category chips so the pre-filter matches.
  static const _services = [
    (label: 'Electrician', icon: Icons.electrical_services_rounded, color: Color(0xFFF59E0B)),
    (label: 'Plumber', icon: Icons.plumbing_rounded, color: Color(0xFF3B82F6)),
    (label: 'Driver', icon: Icons.directions_car_rounded, color: Color(0xFF10B981)),
    (label: 'Cleaner', icon: Icons.cleaning_services_rounded, color: Color(0xFF8B5CF6)),
    (label: 'Nurse', icon: Icons.medical_services_rounded, color: Color(0xFFE8173A)),
    (label: 'Carpenter', icon: Icons.carpenter_rounded, color: Color(0xFFB45309)),
    (label: 'Painter', icon: Icons.format_paint_rounded, color: Color(0xFFEC4899)),
    (label: 'Cook', icon: Icons.restaurant_rounded, color: Color(0xFFFF8C00)),
  ];

  @override
  Widget build(BuildContext context) {
    // Grab-style launcher: 4×2 grid — first 7 services + "All" tile that
    // opens the full list in a bottom sheet.
    final visible = _services.take(7).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Quick services',
            trailing: 'Typical arrival 15–30 min'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: [
              for (final s in visible)
                _ServiceTile(
                  label: s.label,
                  icon: s.icon,
                  color: s.color,
                  // Service-first (Uber model): straight to the broadcast
                  // request for this service — no pro list, no picking.
                  onTap: () => _push(
                      context, InstantRequestScreen(skill: s.label)),
                ),
              _ServiceTile(
                label: 'All',
                icon: Icons.grid_view_rounded,
                color: context.gx.accent,
                onTap: () => _showAllServices(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAllServices(BuildContext context) {
    showGxSheet(
      context,
      title: 'All services',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _services)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(s.icon, color: s.color, size: 21),
                ),
                title: Text(s.label,
                    style: TextStyle(
                        color: context.gx.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                trailing: Icon(Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: context.gx.ink.withValues(alpha: 0.35)),
                onTap: () {
                  Navigator.pop(context);
                  _push(context, InstantRequestScreen(skill: s.label));
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GxPressable(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}

// ── Popular Events — neutral "gx-ev" cards (emoji · name · subtitle) ──────
class PopularEventsStrip extends StatelessWidget {
  const PopularEventsStrip({super.key});

  // Matches Gixbee_home_v106.html "Popular Events".
  static const _events = [
    (emoji: '💍', label: 'Wedding', sub: 'Photo · catering · décor'),
    (emoji: '⛪', label: 'Baptism', sub: 'Photo · catering'),
    (emoji: '💐', label: 'Engagement', sub: 'Décor · photo'),
    (emoji: '🎂', label: 'Birthday', sub: 'Cake · décor · DJ'),
    (emoji: '🏠', label: 'Housewarming', sub: 'Catering · priest'),
    (emoji: '🕯️', label: 'Memorial', sub: 'Catering · arrangements'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (context, i) {
          final e = _events[i];
          return MergeSemantics(
            child: GxPressable(
            onTap: () => _push(
                context, BookServicesSplitScreen(initialEventType: e.label)),
            child: Container(
              width: 106,
              padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
              decoration: BoxDecoration(
                color: context.gx.card,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: context.gx.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                      child:
                          Text(e.emoji, style: TextStyle(fontSize: 24))),
                  SizedBox(height: 8),
                  Text(e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink)),
                  SizedBox(height: 2),
                  Text(e.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: context.gx.ink.withValues(alpha: 0.55))),
                ],
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}

// ── Today's Deals (backed by /master-entries?type=DEAL) ───────────────────
class DealEntry {
  final String id;
  final String title;
  final String code;
  final String? subtitle;

  const DealEntry({
    required this.id,
    required this.title,
    required this.code,
    this.subtitle,
  });

  factory DealEntry.fromMap(Map<String, dynamic> map) {
    return DealEntry(
      id: map['id'] as String,
      title: map['label'] as String,
      code: map['value'] as String,
      subtitle: map['category'] as String?,
    );
  }
}

// Local placeholder promos shown until real deals are seeded via the
// master-entries admin API (POST /master-entries, type: DEAL).
const _fallbackDeals = [
  DealEntry(
    id: 'local-1',
    title: 'Flat ₹100 off your first booking',
    code: 'GIX100',
    subtitle: 'New customers · any service',
  ),
  DealEntry(
    id: 'local-2',
    title: '10% off event services this week',
    code: 'EVENT10',
    subtitle: 'Hall, catering, decor & more',
  ),
  DealEntry(
    id: 'local-3',
    title: 'Free visit charge on Instant Help',
    code: 'INSTANTFREE',
    subtitle: 'Today only',
  ),
];

final dealsProvider = FutureProvider<List<DealEntry>>((ref) async {
  final dio = ref.watch(dioProvider);
  // City scoping: global deals + deals targeted at the selected serviceable
  // city; refetches automatically when the user switches city.
  final city = ref.watch(currentCityProvider);
  try {
    final response = await dio.get('/master-entries', queryParameters: {
      'type': 'DEAL',
      'isActive': true,
      if (city != null) 'cityId': city.id,
    });
    final data = response.data as List;
    final deals = data
        .map((item) => DealEntry.fromMap(item as Map<String, dynamic>))
        .toList();
    if (deals.isNotEmpty) return deals;
  } catch (e) {
    debugPrint('Error fetching deals: $e');
  }
  return _fallbackDeals;
});

class DealsStrip extends ConsumerWidget {
  const DealsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(dealsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: deals.when(
        loading: () =>
            const GxSkeleton(width: double.infinity, height: 196, radius: 18),
        error: (_, __) => const _FeaturedOffer(deals: _fallbackDeals),
        data: (items) =>
            _FeaturedOffer(deals: items.isEmpty ? _fallbackDeals : items),
      ),
    );
  }
}

/// Single prominent "gx-fd" featured-offer card (matches the mockup's
/// Today's Offers block). Tapping it — or the Claim button — copies the code.
class _FeaturedOffer extends StatelessWidget {
  const _FeaturedOffer({required this.deals});

  final List<DealEntry> deals;

  Future<void> _claim(BuildContext context, DealEntry d) async {
    showGxSheet(
      context,
      title: 'Claimed from',
      child: ClaimDealSheet(deal: d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = deals.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GxPressable(
          onTap: () => _claim(context, d),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.gx.card2,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.gx.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color:
                            context.gx.accentSoft.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.local_offer_rounded,
                          color: context.gx.accentSoft, size: 22),
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.subtitle ?? 'Gixbee Partner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: context.gx.ink)),
                          SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.verified_rounded,
                                  size: 13, color: Color(0xFF22C55E)),
                              SizedBox(width: 3),
                              Text('Verified offer',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF22C55E))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFFF43F5E), Color(0xFFBE123C)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('HOT',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: context.gx.onAccent)),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Text(d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color: context.gx.ink)),
                SizedBox(height: 6),
                Text('Limited time · tap to claim',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.gx.ink.withValues(alpha: 0.55))),
                SizedBox(height: 13),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: context.gx.ink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.confirmation_number_outlined,
                              size: 14, color: context.gx.ink),
                          SizedBox(width: 5),
                          Text(d.code,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: context.gx.ink)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    GxPressable(
                      onTap: () => _claim(context, d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFFF5B301), Color(0xFFC98A00)]),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Text('Claim',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1200))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (deals.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < deals.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: i == 0 ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? const Color(0xFFF5B301)
                        : context.gx.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── College Banner ──────────────────────────────────────────────────────────
class CollegeBanner extends StatelessWidget {
  const CollegeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0A2A), Color(0xFF0E1440), Color(0xFF0A1A10)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.gx.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: context.gx.ink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school_rounded, size: 10, color: Colors.white),
                  SizedBox(width: 4),
                  Text('COLLEGE SPECIAL',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ],
              ),
            ),
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kickstart Your Career\nwith Opportunities!',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          children: [
                            TextSpan(text: 'Internships', style: TextStyle(color: context.gx.accentSoft)),
                            TextSpan(text: ' • ', style: TextStyle(color: Colors.white54)),
                            TextSpan(text: 'Part-time Jobs', style: TextStyle(color: GixbeeTheme.accentGold)),
                            TextSpan(text: ' • ', style: TextStyle(color: Colors.white54)),
                            TextSpan(text: 'Training', style: TextStyle(color: GixbeeTheme.accentGreen)),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      Text('Explore, Learn & Grow with Gixbee',
                          style: TextStyle(fontSize: 11, color: Colors.white54)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: GixbeeTheme.accentGold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Explore Now ↗',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F0800))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: context.gx.accentSoft.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.work_outline_rounded,
                          color: context.gx.accentSoft, size: 22),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: GixbeeTheme.accentGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: GixbeeTheme.accentGold, size: 22),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Claim Deal Sheet ────────────────────────────────────────────────────────
class ClaimDealSheet extends StatelessWidget {
  final DealEntry deal;
  const ClaimDealSheet({super.key, required this.deal});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(deal.subtitle ?? 'Gixbee Partner',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.gx.ink)),
        SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.06),
            border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text('Show this code at the store',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: context.gx.ink.withValues(alpha: 0.55))),
              SizedBox(height: 9),
              Text(deal.code,
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3.0,
                      color: Color(0xFF22C55E))),
              const SizedBox(height: 9),
              Text(deal.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF22C55E))),
              const SizedBox(height: 9),
              Text('Claimed just now',
                  style: TextStyle(
                      fontSize: 11,
                      color: context.gx.ink.withValues(alpha: 0.55))),
              SizedBox(height: 2),
              Text('Valid till tonight',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GixbeeTheme.accentGold)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: context.gx.ink.withValues(alpha: 0.05),
            border: Border.all(color: context.gx.border),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_rounded, color: context.gx.ink.withValues(alpha: 0.55), size: 16),
              SizedBox(width: 7),
              Text('Available at nearest outlet',
                  style: TextStyle(
                      fontSize: 13,
                      color: context.gx.ink.withValues(alpha: 0.55))),
            ],
          ),
        ),
        SizedBox(height: 14),
        GxPressable(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: context.gx.ink.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text('Done',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.gx.ink)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
