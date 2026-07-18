import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../services/location_service.dart';
import '../../services/location_bootstrap.dart';
import '../../repositories/auth_repository.dart'; // currentUserProvider
import '../../repositories/cities_repository.dart'; // currentCityProvider
import '../booking/book_services_split_screen.dart';
import 'home_location_picker_screen.dart';
import '../jobs/find_job_module.dart';
import '../business/list_business_type_screen.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_pressable.dart';
import 'home_sections.dart';
import 'todays_offers_screen.dart';
import '../jobs/register_pro_screen.dart';
import '../worker/go_live_screen.dart';
import '../booking/instant_help_screen.dart';
import '../rentals/rentals_catalog_screen.dart';
import 'active_booking_card.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';

/// Home — rebuilt to match the user's `Gixbee_home_v106.html` mockup:
/// orange wordmark + location bar, search, a 2×2 colour-coded service quad,
/// a "Gixbee for Business" button, Today's Offers, banner carousel, Popular
/// Events, an "explore all" row, and a 5-item trust strip. The main-app
/// accent is now violet (context.gx.accent/Violet); the wordmark keeps
/// the orange brand gradient.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _locationBar(context, ref)),
              SliverToBoxAdapter(child: _searchBar(context)),
              const SliverToBoxAdapter(child: ActiveBookingCard()),
              SliverToBoxAdapter(child: _servicesQuad(context, ref)),
              // NEW Rentals module — its own entry beside Plan an Event
              // (client: "don't drop Plan an Event, I need new as rental").
              SliverToBoxAdapter(child: _rentalsButton(context)),
              SliverToBoxAdapter(child: _businessButton(context)),
              SliverToBoxAdapter(
                child: _secRow(context, "Today's Offers",
                    onTap: () => _go(context, const TodaysOffersScreen())),
              ),
              const SliverToBoxAdapter(child: DealsStrip()),
              const SliverToBoxAdapter(
                child: CollegeBanner(),
              ),
              SliverToBoxAdapter(
                child: _secRow(context, 'Popular Events',
                    onTap: () => _go(context, const BookServicesSplitScreen())),
              ),
              const SliverToBoxAdapter(child: PopularEventsStrip()),
              SliverToBoxAdapter(child: _exploreAllRow(context)),
              SliverToBoxAdapter(child: _trustRow(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // ── Location bar: wordmark · separator · location · bell · avatar ────────
  Widget _locationBar(BuildContext context, WidgetRef ref) {
    final address = ref.watch(currentAddressProvider);
    final user = ref.watch(currentUserProvider).value;
    final initial = (user?.name?.trim().isNotEmpty ?? false)
        ? user!.name!.trim()[0].toUpperCase()
        : 'G';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          // Orange wordmark (brand gradient kept).
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: GixbeeTheme.brandGradient,
            ).createShader(bounds),
            child: Text(
              'gixbee',
              style: GoogleFonts.nunito(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 1),
            child: Text('®',
                style: TextStyle(
                    color: GixbeeTheme.brandRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            color: context.gx.border,
          ),
          // Location (tappable → picker).
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pickLocation(context, ref),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          color: context.gx.accentSoft, size: 14),
                      SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down,
                          size: 15, color: context.gx.ink.withValues(alpha: 0.55)),
                    ],
                  ),
                  Text('Tap to change location',
                      style: TextStyle(fontSize: 11, color: context.gx.ink.withValues(alpha: 0.55))),
                ],
              ),
            ),
          ),
          SizedBox(width: 8),
          // Notification bell with dot.
          Semantics(
            button: true,
            label: 'Notifications',
            child: GxPressable(
            onTap: () => _go(context, const NotificationsScreen()),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.gx.card2,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 19, color: context.gx.ink),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: context.gx.bg, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
          SizedBox(width: 10),
          // Avatar with online dot.
          GxPressable(
            onTap: () => _go(context, const ProfileScreen()),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [context.gx.accentSoft, GixbeeTheme.accentPink],
                ),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Text(initial,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.gx.onAccent)),
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: GixbeeTheme.accentGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: context.gx.bg, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLocation(BuildContext context, WidgetRef ref) async {
    final location = await Navigator.push<HomePickedLocation>(
      context,
      MaterialPageRoute(builder: (_) => const HomeLocationPickerScreen()),
    );
    if (location != null) {
      // Sets all three providers AND persists to secure storage so the pick
      // survives app restarts (restored by ensureLocationInitialized).
      await applyLocation(
        ref,
        address: location.address,
        lat: location.lat,
        lng: location.lng,
        city: location.city,
      );
    }
  }

  // ── Search bar (purple mic) ──────────────────────────────────────────────
  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GxPressable(
        // Uber/Grab model everywhere: search leads to the service-first
        // Instant Help flow — the customer never picks a person.
        onTap: () => _go(context, const InstantHelpScreen()),
        child: Container(
          decoration: BoxDecoration(
            color: context.gx.card2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.gx.border, width: 1.5),
          ),
          padding: const EdgeInsets.fromLTRB(14, 9, 9, 9),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  color: context.gx.ink.withValues(alpha: 0.55), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search services, jobs, professionals, businesses…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.gx.ink.withValues(alpha: 0.55), fontSize: 13),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: context.gx.accentGradient),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded,
                    color: Colors.white, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Service quad (2×2 colour-coded cards) ────────────────────────────────
  Widget _servicesQuad(BuildContext context, WidgetRef ref) {
    final cards = <_QuadData>[
      _QuadData(
        title: 'Find a Job',
        tag: 'Full/part-time, contract & internships',
        icon: Icons.work_outline_rounded,
        accent: GixbeeTheme.accentGreen,
        tileColors: const [Color(0xFF10B981), Color(0xFF047857)],
        onTap: () => _go(context, const FindJobModule()),
      ),
      _QuadData(
        title: 'Earn Hourly',
        tag: 'Work nearby · paid fast',
        icon: Icons.schedule_rounded,
        accent: GixbeeTheme.accentGold,
        tileColors: const [Color(0xFFF59E0B), Color(0xFFB45309)],
        // Registered pros go straight to the Go Live dashboard; only new
        // users see the onboarding wizard. Without this, every login forced
        // the full register + verify flow again (hasWorkerProfile fix pairs
        // with this on the backend).
        onTap: () {
          final user = ref.read(currentUserProvider).value;
          _go(
            context,
            (user?.isWorker ?? false)
                ? const GoLiveScreen()
                : const RegisterProScreen(),
          );
        },
      ),
      _QuadData(
        title: 'Instant Help',
        tag: 'At your door in 15–45 min',
        icon: Icons.bolt_rounded,
        accent: context.gx.accentSoft,
        tileColors: context.gx.accentGradient,
        // Uber/Grab model: pick the SERVICE, not the person — the request is
        // broadcast to all nearby live pros, first accept wins.
        onTap: () => _go(context, const InstantHelpScreen()),
      ),
      _QuadData(
        title: 'Plan an Event',
        tag: 'Events, rentals & shop offers',
        icon: Icons.calendar_month_rounded,
        accent: GixbeeTheme.accentPink,
        tileColors: const [Color(0xFFEC4899), Color(0xFFBE185D)],
        onTap: () => _go(context, const BookServicesSplitScreen()),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 1.45,
        children: [for (final c in cards) _quadCard(context, c)],
      ),
    );
  }

  Widget _quadCard(BuildContext context, _QuadData d) {
    return GxPressable(
      onTap: d.onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-0.4, -1),
            end: Alignment.bottomRight,
            colors: [d.accent.withValues(alpha: 0.20), context.gx.card],
            stops: const [0, 0.62],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.accent.withValues(alpha: 0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: d.accent.withValues(alpha: 0.22),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: d.tileColors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(d.icon, color: Colors.white, size: 20),
              ),
              SizedBox(height: 8),
              Text(d.title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: context.gx.ink)),
              SizedBox(height: 3),
              Expanded(
                child: Text(d.tag,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        height: 1.28,
                        fontWeight: FontWeight.w500,
                        color: context.gx.ink.withValues(alpha: 0.55))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Rentals (teal) — NEW module, sits beside Plan an Event ──────────────
  Widget _rentalsButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
      child: GxPressable(
        onTap: () => _go(context, const RentalsCatalogScreen()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.4, -1),
              end: Alignment.bottomRight,
              colors: [
                GixbeeTheme.accentTeal.withValues(alpha: 0.16),
                GixbeeTheme.accentTeal.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: GixbeeTheme.accentTeal.withValues(alpha: 0.26)),
            boxShadow: [
              BoxShadow(
                color: GixbeeTheme.accentTeal.withValues(alpha: 0.5),
                blurRadius: 22,
                spreadRadius: -12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: MergeSemantics(
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.handyman_rounded,
                      color: Colors.white, size: 19),
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rentals',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.gx.ink)),
                      SizedBox(height: 2),
                      Text('Rent tools, gear & event supplies — or list yours',
                          style:
                              TextStyle(fontSize: 10.5, color: context.gx.ink.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: GixbeeTheme.accentTeal, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Gixbee for Business (blue) ───────────────────────────────────────────
  Widget _businessButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
      child: GxPressable(
        onTap: () => _go(context, const ListBusinessTypeScreen()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.4, -1),
              end: Alignment.bottomRight,
              colors: [
                GixbeeTheme.accentBlue.withValues(alpha: 0.16),
                GixbeeTheme.accentBlue.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: GixbeeTheme.accentBlue.withValues(alpha: 0.26)),
            boxShadow: [
              BoxShadow(
                color: GixbeeTheme.accentBlue.withValues(alpha: 0.5),
                blurRadius: 22,
                spreadRadius: -12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: MergeSemantics(
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.storefront_rounded,
                      color: Colors.white, size: 19),
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gixbee for Business',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.gx.ink)),
                      SizedBox(height: 2),
                      Text('List your business, or hire staff & interns',
                          style:
                              TextStyle(fontSize: 10.5, color: context.gx.ink.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: GixbeeTheme.accentBlue, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── "Explore all services & events" row ──────────────────────────────────
  Widget _exploreAllRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: GxPressable(
        onTap: () => _go(context, const BookServicesSplitScreen()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
          decoration: BoxDecoration(
            color: context.gx.ink.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.gx.border),
          ),
          child: MergeSemantics(
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: context.gx.accentSoft.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.apps_rounded,
                      color: context.gx.accentSoft, size: 17),
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Explore all services & events',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.gx.ink)),
                      SizedBox(height: 2),
                      Text('50+ vendors, packages & rentals',
                          style:
                              TextStyle(fontSize: 10.5, color: context.gx.ink.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: context.gx.accentSoft, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Trust badges (5 items) ───────────────────────────────────────────────
  Widget _trustRow(BuildContext context) {
    final items = <(IconData, Color, String)>[
      (Icons.badge_outlined, context.gx.accentSoft, 'Aadhaar\nVerified'),
      (Icons.how_to_reg_rounded, GixbeeTheme.accentGreen, 'Background\nChecked'),
      (Icons.star_rounded, GixbeeTheme.accentGold, 'Up to 4.8★\nWorker Rating'),
      (Icons.verified_user_rounded, GixbeeTheme.accentBlue, 'Service\nGuarantee'),
      (Icons.lock_rounded, GixbeeTheme.accentTeal, 'Secure\nPayments'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: i == items.length - 1
                      ? null
                      : Border(
                          right: BorderSide(color: context.gx.border)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Icon(items[i].$1, color: items[i].$2, size: 17),
                    SizedBox(height: 5),
                    Text(items[i].$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: context.gx.ink.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Section header with a "View all" link ────────────────────────────────
  Widget _secRow(BuildContext context, String title,
      {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: context.gx.ink)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              children: [
                Text('View all',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.gx.accentSoft)),
                SizedBox(width: 3),
                Icon(Icons.arrow_forward_rounded,
                    size: 12, color: context.gx.accentSoft),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuadData {
  final String title;
  final String tag;
  final IconData icon;
  final Color accent;
  final List<Color> tileColors;
  final VoidCallback onTap;

  _QuadData({
    required this.title,
    required this.tag,
    required this.icon,
    required this.accent,
    required this.tileColors,
    required this.onTap,
  });
}
