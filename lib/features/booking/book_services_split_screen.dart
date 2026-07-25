import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'instant_request_screen.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_glass_card.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_calendar.dart';

/// Plan an Event module — matches the mockup's "pa" (Plan Ahead) sub-app.
/// Pick an event type, select the services you need (hall, catering, decor,
/// photography…), set date + guest count, then find pros for each service.
class BookServicesSplitScreen extends StatefulWidget {
  const BookServicesSplitScreen({super.key, this.initialEventType});

  /// Optional event-type label (e.g. 'Wedding') to pre-select — used by the
  /// home screen's Popular Events strip.
  final String? initialEventType;

  @override
  State<BookServicesSplitScreen> createState() =>
      _BookServicesSplitScreenState();
}

class _BookServicesSplitScreenState extends State<BookServicesSplitScreen> {
  int _eventTypeIndex = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEventType;
    if (initial != null) {
      final i = _eventTypes.indexWhere((e) => e.label == initial);
      if (i >= 0) _eventTypeIndex = i;
    }
  }
  final Set<String> _selectedServices = {};
  DateTime? _eventDate;
  int _guests = 100;

  static const _eventTypes = [
    (label: 'Wedding', icon: Icons.favorite_rounded),
    (label: 'Birthday', icon: Icons.cake_rounded),
    (label: 'Corporate', icon: Icons.business_center_rounded),
    (label: 'Housewarming', icon: Icons.home_rounded),
    (label: 'Engagement', icon: Icons.diamond_rounded),
    (label: 'Other', icon: Icons.celebration_rounded),
  ];

  static const _services = [
    (label: 'Hall', icon: Icons.location_city_rounded, color: Color(0xFF8B5CF6)),
    (label: 'Catering', icon: Icons.restaurant_rounded, color: Color(0xFFFF8C00)),
    (label: 'Decor', icon: Icons.auto_awesome_rounded, color: Color(0xFFEC4899)),
    (label: 'Photography', icon: Icons.photo_camera_rounded, color: Color(0xFF3B82F6)),
    (label: 'Music / DJ', icon: Icons.music_note_rounded, color: Color(0xFF10B981)),
    (label: 'Makeup', icon: Icons.brush_rounded, color: Color(0xFFF59E0B)),
    (label: 'Mehendi', icon: Icons.front_hand_rounded, color: Color(0xFFE8173A)),
    (label: 'Invitations', icon: Icons.mail_rounded, color: Color(0xFF6366F1)),
  ];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showGxCalendar(
      context,
      title: 'Event date',
      initialDate: _eventDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      accent: GixbeeTheme.accentPink,
      accentGradient: const [GixbeeTheme.accentPink, Color(0xFFBE185D)],
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  void _findPros() {
    if (_selectedServices.isEmpty) {
      showGxSnack(context, 'Select at least one service to continue');
      return;
    }
    // Uber/Grab model (user decision 2026-07-04): no pros list here either —
    // go straight to the broadcast request for the first selected service.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InstantRequestScreen(skill: _selectedServices.first),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _hero(context)),
                    SliverToBoxAdapter(child: _sectionTitle(context, 'What are you celebrating?')),
                    SliverToBoxAdapter(child: _eventTypeChips(context)),
                    SliverToBoxAdapter(child: _sectionTitle(context, 'Services you need')),
                    SliverToBoxAdapter(child: _serviceGrid(context)),
                    SliverToBoxAdapter(child: _sectionTitle(context, 'Event details')),
                    SliverToBoxAdapter(child: _detailsCard(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
              _bottomCta(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Neutral bento hero header (surgical orange: gradient lives on the
  // bottom CTA only) ───────────────────────────────────────────────────────
  Widget _hero(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gx.card2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.gx.ink.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GxPressable(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
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
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GixbeeTheme.accentPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: GixbeeTheme.accentPink.withValues(alpha: 0.3)),
                ),
                child: Text('PLAN AHEAD',
                    style: TextStyle(
                        color: GixbeeTheme.accentPink,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: GixbeeTheme.accentPink.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.celebration_rounded,
                color: GixbeeTheme.accentPink, size: 28),
          ),
          const SizedBox(height: 12),
          Text('Plan an Event',
              style: TextStyle(
                  color: context.gx.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Hall, catering, decor & photography —\nbook every pro in one place',
              style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4)),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Text(title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              )),
    );
  }

  // ── Event type chips ─────────────────────────────────────────────────────
  Widget _eventTypeChips(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < _eventTypes.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GxPressable(
                onTap: () => setState(() => _eventTypeIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _eventTypeIndex == i
                        ? GixbeeTheme.accentPink.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _eventTypeIndex == i
                          ? GixbeeTheme.accentPink
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(_eventTypes[i].icon,
                          size: 15,
                          color: _eventTypeIndex == i
                              ? GixbeeTheme.accentPink
                              : colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(_eventTypes[i].label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _eventTypeIndex == i
                                ? GixbeeTheme.accentPink
                                : colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Service multi-select grid ────────────────────────────────────────────
  Widget _serviceGrid(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: _services.length,
        itemBuilder: (context, i) {
          final s = _services[i];
          final selected = _selectedServices.contains(s.label);
          return GxPressable(
            onTap: () => setState(() {
              selected
                  ? _selectedServices.remove(s.label)
                  : _selectedServices.add(s.label);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected
                    ? s.color.withValues(alpha: 0.18)
                    : colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? s.color
                      : colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: s.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(s.icon, color: s.color, size: 19),
                      ),
                      if (selected)
                        Positioned(
                          right: -5,
                          top: -5,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: colorScheme.surface, width: 1.5),
                            ),
                            child: Icon(Icons.check,
                                size: 9, color: context.gx.onAccent),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(s.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Date + guests card ───────────────────────────────────────────────────
  Widget _detailsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateLabel = _eventDate == null
        ? 'Pick a date'
        : '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GxGlassCard(
        padding: const EdgeInsets.all(14),
        radius: 16,
        child: Row(
        children: [
          // Date picker
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(Icons.event_rounded,
                      color: GixbeeTheme.accentPink, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Event date',
                            style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant)),
                        Text(dateLabel,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
              width: 1,
              height: 32,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(width: 12),
          // Guest stepper
          Icon(Icons.groups_rounded, color: GixbeeTheme.accentPink, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Guests',
                  style: TextStyle(
                      fontSize: 10, color: colorScheme.onSurfaceVariant)),
              Row(
                children: [
                  _stepBtn(context, Icons.remove_rounded,
                      () => setState(() => _guests = (_guests - 50).clamp(10, 5000).toInt())),
                  SizedBox(
                    width: 44,
                    child: Text('$_guests',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                  _stepBtn(context, Icons.add_rounded,
                      () => setState(() => _guests = (_guests + 50).clamp(10, 5000).toInt())),
                ],
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    return GxPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: GixbeeTheme.accentPink.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14, color: GixbeeTheme.accentPink),
      ),
    );
  }

  // ── Bottom CTA ───────────────────────────────────────────────────────────
  Widget _bottomCta(BuildContext context) {
    final count = _selectedServices.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: GxPressable(
        onTap: _findPros,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            // v106: Plan an Event uses the pink accent (home quad colour-coding).
            gradient: const LinearGradient(
                colors: [GixbeeTheme.accentPink, Color(0xFFBE185D)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_rounded, color: context.gx.onAccent, size: 19),
              const SizedBox(width: 8),
              Text(
                count == 0
                    ? 'Find pros for my event'
                    : 'Find pros · $count service${count == 1 ? '' : 's'} selected',
                style: TextStyle(
                    color: context.gx.onAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
