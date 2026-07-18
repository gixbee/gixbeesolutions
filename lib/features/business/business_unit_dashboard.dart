import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/business_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/glass_container.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_calendar.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import '../jobs/post_job_screen.dart';
import 'hiring_pipeline_screen.dart';
import 'list_business_type_screen.dart';

/// The signed-in owner's businesses. autoDispose so it re-fetches on each visit
/// and after add-operator / mark-offline mutations invalidate it.
final myBusinessesProvider =
    FutureProvider.autoDispose<List<Business>>((ref) async {
  return ref.watch(businessRepositoryProvider).getMyBusinesses();
});

class BusinessUnitDashboard extends ConsumerWidget {
  const BusinessUnitDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessesAsync = ref.watch(myBusinessesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Businesses'),
        centerTitle: true,
      ),
      body: businessesAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: 4,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: GxSkeleton(width: double.infinity, height: 132, radius: 20),
          ),
        ),
        error: (e, _) => RefreshIndicator(
          onRefresh: () => ref.refresh(myBusinessesProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.16),
              const GxEmptyState(
                icon: Icons.storefront_outlined,
                title: 'Couldn\'t load your businesses',
                message: 'Pull down to refresh, or try again in a moment.',
                accent: GixbeeTheme.accentBlue,
              ),
            ],
          ),
        ),
        data: (businesses) {
          if (businesses.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(myBusinessesProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                      height: MediaQuery.of(context).size.height * 0.16),
                  const GxEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No businesses yet',
                    message:
                        'List your shop, hall, or hiring unit to manage it here.',
                    accent: GixbeeTheme.accentBlue,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myBusinessesProvider.future),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: businesses.length,
              itemBuilder: (context, index) =>
                  _BusinessCard(business: businesses[index]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GixbeeTheme.accentBlue,
        foregroundColor: context.gx.onAccent,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ListBusinessTypeScreen(),
            ),
          );
          ref.invalidate(myBusinessesProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Business'),
      ),
    );
  }
}

/// A single business unit card — header (icon, name, status chip) + the
/// type-specific action row. Hiring units → Post Job / Candidates; service &
/// rental units → Calendar (offline-day availability) / Operators.
class _BusinessCard extends ConsumerWidget {
  final Business business;
  const _BusinessCard({required this.business});

  bool get _isHiring => business.type == 'HIRING';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Squircle business-type icon block
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: GixbeeTheme.accentBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    _isHiring ? Icons.work_outline : Icons.handyman_outlined,
                    color: GixbeeTheme.accentBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isHiring ? 'Hiring Unit' : 'Service Unit',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: business.status),
              ],
            ),
            const SizedBox(height: 18),
            // Type-specific action buttons
            Row(
              children: [
                if (_isHiring) ...[
                  Expanded(
                    child: _BizAction(
                      icon: Icons.add,
                      label: 'Post Job',
                      primary: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PostJobScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BizAction(
                      icon: Icons.people_outline,
                      label: 'Candidates',
                      primary: false,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HiringPipelineScreen(
                            jobId: 'all',
                            jobTitle: 'All Active Postings',
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: _BizAction(
                      icon: Icons.calendar_month,
                      label: 'Calendar',
                      primary: true,
                      onTap: () => _markOfflineDay(context, ref, business),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BizAction(
                      icon: Icons.person_add_alt,
                      label: 'Operators',
                      primary: false,
                      onTap: () => _manageOperators(context, ref, business),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Calendar: pick a free day to mark the unit offline. Existing offline
  // days arrive as `blockedDays` (rendered struck-through, non-selectable), so
  // the sheet doubles as the availability view. Backend only supports ADD
  // (POST /businesses/:id/calendar/offline) today — there is no remove yet.
  Future<void> _markOfflineDay(
      BuildContext context, WidgetRef ref, Business biz) async {
    final picked = await showGxCalendar(
      context,
      title: 'Mark a day offline',
      blockedDays: biz.offlineDays.toSet(),
      accent: GixbeeTheme.accentBlue,
      accentGradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
    );
    if (picked == null) return;
    try {
      await ref.read(businessRepositoryProvider).addOfflineDay(biz.id, picked);
      ref.invalidate(myBusinessesProvider);
      if (context.mounted) {
        showGxSnack(
          context,
          'Marked ${picked.day}/${picked.month}/${picked.year} as offline',
          type: GxSnackType.success,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showGxSnack(context, 'Could not update calendar',
            type: GxSnackType.error);
      }
    }
  }

  // ── Operators: a glass sheet listing current operators + an add-by-id field
  // (the backend grants access by raw user id — POST /businesses/:id/operators).
  Future<void> _manageOperators(
      BuildContext context, WidgetRef ref, Business biz) async {
    await showGxSheet<void>(
      context,
      title: 'Operators',
      child: _OperatorsSheet(business: biz),
    );
  }
}

/// Status pill reflecting the real verification state.
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'VERIFIED' => (Colors.green, Icons.verified, 'VERIFIED'),
      'REJECTED' => (Colors.redAccent, Icons.cancel_outlined, 'REJECTED'),
      _ => (const Color(0xFFFBBF24), Icons.schedule_rounded, 'PENDING'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Operators management sheet — current operator ids + add-by-id form. Held as
/// its own ConsumerStatefulWidget so the busy/loading flag survives rebuilds
/// (an inline StatefulBuilder local would reset each frame).
class _OperatorsSheet extends ConsumerStatefulWidget {
  final Business business;
  const _OperatorsSheet({required this.business});

  @override
  ConsumerState<_OperatorsSheet> createState() => _OperatorsSheetState();
}

class _OperatorsSheetState extends ConsumerState<_OperatorsSheet> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  late List<String> _operators;
  bool _busy = false;

  // P106 operator picker: name/phone lookup over GET /admin-user-list/search.
  List<UserLookupResult> _results = const [];
  bool _searching = false;
  int _searchSeq = 0; // guards against out-of-order async responses

  @override
  void initState() {
    super.initState();
    _operators = List<String>.from(widget.business.operatorIds);
  }

  @override
  void dispose() {
    _idController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    final seq = ++_searchSeq;
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final hits = await ref.read(businessRepositoryProvider).searchUsers(q);
      if (!mounted || seq != _searchSeq) return; // a newer query superseded this
      setState(() {
        _results = hits;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() => _searching = false);
      showGxSnack(context, 'Could not search users', type: GxSnackType.error);
    }
  }

  /// Shared add path — used by both the picked-result tap and the manual-id
  /// fallback. [label] is the human-readable name (or the id) for the toast.
  Future<void> _addOperator(String id, String label) async {
    if (id.isEmpty || _busy) return;
    if (_operators.contains(id)) {
      showGxSnack(context, 'Already an operator', type: GxSnackType.info);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(businessRepositoryProvider)
          .addOperator(widget.business.id, id, 'operator');
      ref.invalidate(myBusinessesProvider);
      if (!mounted) return;
      setState(() {
        _operators.add(id);
        _idController.clear();
        _searchController.clear();
        _results = const [];
        _busy = false;
      });
      showGxSnack(context, 'Added $label', type: GxSnackType.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGxSnack(context, 'Could not add operator', type: GxSnackType.error);
    }
  }

  void _add() {
    final id = _idController.text.trim();
    _addOperator(id, id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _operators.isEmpty
              ? 'No operators yet'
              : '${_operators.length} operator${_operators.length == 1 ? '' : 's'}',
          style: TextStyle(
              color: context.gx.ink, fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (final op in _operators)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.person_outline,
                    size: 16, color: GixbeeTheme.accentBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    op,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text('ADD OPERATOR',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        GxTextField(
          controller: _searchController,
          accent: GixbeeTheme.accentBlue,
          hint: 'Search by name or phone',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: _runSearch,
          onSubmitted: _runSearch,
          suffix: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: GixbeeTheme.accentBlue),
                  ),
                )
              : null,
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final u in _results)
            _OperatorResultRow(
              user: u,
              alreadyAdded: _operators.contains(u.id),
              onTap: _busy || _operators.contains(u.id)
                  ? null
                  : () => _addOperator(
                      u.id, u.name.isEmpty ? u.id : u.name),
            ),
        ] else if (!_searching && _searchController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('No matching users',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 14),
        Text('OR ADD BY USER ID',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        GxTextField(
          controller: _idController,
          accent: GixbeeTheme.accentBlue,
          hint: 'Operator\'s user ID',
          prefixIcon: Icons.badge_outlined,
        ),
        const SizedBox(height: 14),
        GxButton(
          label: 'Add operator',
          onTap: _add,
          loading: _busy,
          accent: GixbeeTheme.accentBlue,
          gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
        ),
      ],
    );
  }
}

/// A single tappable search result in the operator picker — name, phone/role
/// subtitle, and a +/✓ trailing affordance. Display-only when [onTap] is null
/// (already an operator or a mutation is in flight).
class _OperatorResultRow extends StatelessWidget {
  final UserLookupResult user;
  final bool alreadyAdded;
  final VoidCallback? onTap;

  const _OperatorResultRow({
    required this.user,
    required this.alreadyAdded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = user.phoneNumber ?? user.role ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GxPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.gx.ink.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.gx.ink.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: GixbeeTheme.accentBlue.withValues(alpha: 0.18),
                child: Text(
                  (user.name.isNotEmpty ? user.name[0] : '?').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: GixbeeTheme.accentBlue),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isEmpty ? 'Unnamed user' : user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                alreadyAdded
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                size: 20,
                color: alreadyAdded
                    ? GixbeeTheme.accentBlue
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v106 business-unit action button — a violet-free, blue accented pill.
/// `primary` = filled blue gradient; otherwise a soft outlined blue tile.
class _BizAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _BizAction({
    required this.icon,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GxPressable(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  colors: [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
                )
              : null,
          color: primary ? null : GixbeeTheme.accentBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: primary
              ? null
              : Border.all(color: GixbeeTheme.accentBlue.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: primary ? context.gx.onAccent : GixbeeTheme.accentBlue,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: primary ? context.gx.onAccent : GixbeeTheme.accentBlue,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
