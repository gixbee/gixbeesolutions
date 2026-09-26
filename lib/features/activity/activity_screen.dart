import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/main_tab_provider.dart';
import '../../repositories/activity_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../theme.dart';
import 'activity_navigation.dart';

/// Unified Activity tab (replaces bottom-nav Bookings).
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.initialCategory});

  /// `all`, `services`, `rentals`, `events`, `job_applications`, `hiring`
  final String? initialCategory;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  static const _categories = [
    ('all', 'All'),
    ('services', 'Services'),
    ('rentals', 'Rentals'),
    ('events', 'Events'),
    ('job_applications', 'Job Applications'),
    ('hiring', 'Hiring'),
  ];

  String _category = 'all';
  String _phase = 'active';
  String? _statusGroup;
  int _page = 1;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  List<Map<String, dynamic>> _items = [];
  List<String> _categoriesAvailable = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
      _category = widget.initialCategory!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore && !reset) return;
    if (reset) {
      _generation++;
      _page = 1;
      _hasMore = true;
      _items = [];
      _error = null;
      setState(() => _loading = true);
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    final gen = _generation;
    try {
      final page = await ref.read(activityRepositoryProvider).fetchFeed(
            category: _category == 'all' ? null : _category,
            phase: _phase,
            statusGroup: _statusGroup,
            page: _page,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        if (reset) {
          _items = page.items;
        } else {
          final seen = _items.map((e) => e['dedupeKey']).toSet();
          for (final row in page.items) {
            final key = row['dedupeKey'];
            if (key != null && seen.contains(key)) continue;
            _items.add(row);
          }
        }
        _categoriesAvailable = page.categoriesAvailable;
        _hasMore = page.hasMore;
        _page = page.page + 1;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = e;
      });
    }
  }

  void _onCategory(String cat) {
    if (_category == cat) return;
    setState(() {
      _category = cat;
      _statusGroup = null;
    });
    _load(reset: true);
  }

  void _onPhase(String phase) {
    if (_phase == phase) return;
    setState(() {
      _phase = phase;
      _statusGroup = null;
    });
    _load(reset: true);
  }

  static const _activeStatusGroups = {
    'upcoming',
    'in_progress',
    'action_needed',
    'applied',
    'interview',
    'hired',
    'collecting',
    'delivered',
  };

  static const _historyStatusGroups = {
    'completed',
    'closed',
    'withdrawn',
  };

  List<(String, String)> _statusFilters() {
    switch (_category) {
      case 'services':
        return const [
          ('upcoming', 'Upcoming'),
          ('in_progress', 'In progress'),
          ('action_needed', 'Action needed'),
          ('completed', 'Completed'),
          ('closed', 'Closed'),
        ];
      case 'rentals':
        return const [
          ('action_needed', 'Action needed'),
          ('in_progress', 'In progress'),
          ('upcoming', 'Upcoming'),
          ('completed', 'Completed'),
          ('closed', 'Closed'),
        ];
      case 'events':
        return const [
          ('upcoming', 'Upcoming'),
          ('in_progress', 'In progress'),
          ('action_needed', 'Quotes'),
          ('completed', 'Completed'),
          ('closed', 'Closed'),
        ];
      case 'job_applications':
        return const [
          ('applied', 'Applied'),
          ('interview', 'Interview'),
          ('hired', 'Hired'),
          ('closed', 'Closed'),
          ('withdrawn', 'Withdrawn'),
        ];
      case 'hiring':
        return const [
          ('collecting', 'Collecting'),
          ('delivered', 'Delivered'),
          ('closed', 'Closed'),
        ];
      default:
        return const [];
    }
  }

  List<(String, String)> _statusFiltersForPhase() {
    final all = _statusFilters();
    if (_phase == 'active') {
      return all
          .where((f) => !_historyStatusGroups.contains(f.$1))
          .toList();
    }
    if (_phase == 'history') {
      return all.where((f) {
        if (_category == 'events' && f.$1 == 'action_needed') return true;
        return !_activeStatusGroups.contains(f.$1);
      }).toList();
    }
    return all;
  }

  void _onStatusGroup(String? group) {
    var phase = _phase;
    if (group != null) {
      if (_historyStatusGroups.contains(group)) {
        phase = 'history';
      } else if (_activeStatusGroups.contains(group)) {
        if (group == 'action_needed' &&
            _category == 'events' &&
            _phase == 'history') {
          phase = 'history';
        } else {
          phase = 'active';
        }
      }
    }
    setState(() {
      _statusGroup = group;
      _phase = phase;
    });
    _load(reset: true);
  }

  Iterable<Map<String, dynamic>> _visibleItems() {
    final parents = <String>{};
    for (final row in _items) {
      if (row['parentEventId'] == null) {
        parents.add(row['id']?.toString() ?? '');
      }
    }
    return _items.where((row) {
      final parent = row['parentEventId']?.toString();
      if (parent == null || parent.isEmpty) return true;
      return !parents.contains(parent);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(mainTabIndexProvider, (prev, next) {
      if (next == 1 && prev != 1) {
        _load(reset: true);
      }
    });
    ref.listen(myBookingsProvider, (prev, next) {
      if (next.hasValue && prev?.hasValue == true) {
        _load(reset: true);
      }
    });
    ref.listen(currentUserProvider, (prev, next) {
      final prevId = prev?.asData?.value?.id;
      final nextId = next.asData?.value?.id;
      if (prevId != null && nextId != null && prevId != nextId) {
        _load(reset: true);
      }
    });
    final statusFilters = _statusFiltersForPhase();
    final visible = _visibleItems().toList();
    final showCat = (String key) =>
        _category == 'all' ||
        _categoriesAvailable.contains(key) ||
        _categoriesAvailable.isEmpty;

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        backgroundColor: context.gx.bg,
        elevation: 0,
        title: Text(
          'Activity',
          style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w800),
        ),
        iconTheme: IconThemeData(color: context.gx.ink),
        actions: [
          if (_category == 'services' || _category == 'all')
            IconButton(
              tooltip: 'Service booking tabs',
              icon: Icon(Icons.view_list_outlined, color: context.gx.ink),
              onPressed: () =>
                  openServiceBookingsLegacy(context),
            ),
          IconButton(
            tooltip: 'Refresh activity',
            icon: Icon(Icons.refresh, color: context.gx.ink.withValues(alpha: 0.7)),
            onPressed: () => _load(reset: true),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chipRow(
            children: _categories
                .where((c) => c.$1 == 'all' || showCat(c.$1))
                .map(
                  (c) => _filterChip(
                    label: c.$2,
                    selected: _category == c.$1,
                    onTap: () => _onCategory(c.$1),
                  ),
                )
                .toList(),
          ),
          _chipRow(
            children: [
              _filterChip(
                label: 'Active',
                selected: _phase == 'active',
                onTap: () => _onPhase('active'),
              ),
              _filterChip(
                label: 'History',
                selected: _phase == 'history',
                onTap: () => _onPhase('history'),
              ),
            ],
          ),
          if (statusFilters.isNotEmpty)
            _chipRow(
              children: [
                _filterChip(
                  label: 'All statuses',
                  selected: _statusGroup == null,
                  onTap: () => _onStatusGroup(null),
                ),
                ...statusFilters.map(
                  (f) => _filterChip(
                    label: f.$2,
                    selected: _statusGroup == f.$1,
                    onTap: () => _onStatusGroup(f.$1),
                  ),
                ),
              ],
            ),
          Expanded(
            child: _loading && _items.isEmpty
                ? _skeleton()
                : _error != null && _items.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () => _load(reset: true),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: GxNetworkError(
                                error: _error,
                                title: 'Could not load activity',
                                onRetry: () => _load(reset: true),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: context.gx.accent,
                        onRefresh: () => _load(reset: true),
                        child: visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 80),
                                  Icon(Icons.inbox_outlined,
                                      size: 56,
                                      color: context.gx.ink
                                          .withValues(alpha: 0.25)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _phase == 'active'
                                        ? 'No active activity in this view.'
                                        : 'No history in this view.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: context.gx.ink.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ],
                              )
                            : NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.pixels >=
                                          n.metrics.maxScrollExtent - 200 &&
                                      _hasMore &&
                                      !_loadingMore) {
                                    _load();
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 4, 16, 24),
                                  itemCount: visible.length +
                                      (_loadingMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index >= visible.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    }
                                    final row = visible[index];
                                    final children = _items
                                        .where((c) =>
                                            c['parentEventId']?.toString() ==
                                            row['id']?.toString())
                                        .toList();
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _ActivityCard(
                                          item: row,
                                          onTap: () async {
                                            final changed =
                                                await openActivityDetail(
                                              context,
                                              ref,
                                              row,
                                            );
                                            if (changed && mounted) {
                                              _load(reset: true);
                                            }
                                          },
                                        ),
                                        ...children.map(
                                          (c) => Padding(
                                            padding: const EdgeInsets.only(
                                                left: 16, top: 8),
                                            child: _ActivityCard(
                                              item: c,
                                              nested: true,
                                              onTap: () async {
                                                final changed =
                                                    await openActivityDetail(
                                                  context,
                                                  ref,
                                                  c,
                                                );
                                                if (changed && mounted) {
                                                  _load(reset: true);
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chipRow({required List<Widget> children}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: children),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: context.gx.accentSoft,
        checkmarkColor: context.gx.onAccent,
      ),
    );
  }

  Widget _skeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) =>
          const GxSkeleton(width: double.infinity, height: 120, radius: 16),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.item,
    required this.onTap,
    this.nested = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final category = item['category']?.toString() ?? '';
    final title = item['title']?.toString() ?? 'Activity';
    final subtitle = item['subtitle']?.toString() ?? '';
    final counterparty = item['counterparty']?.toString();
    final role = item['roleLabel']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';
    final sortAt = item['sortAt']?.toString();
    final when = sortAt != null
        ? DateFormat('d MMM, h:mm a')
            .format(DateTime.tryParse(sortAt)?.toLocal() ?? DateTime.now())
        : null;
    final extra = item['detail'] is Map
        ? (item['detail'] as Map)['extra']
        : null;
    String? hiringLine;
    if (category == 'hiring' && extra is Map) {
      final interested = extra['interestedCount'];
      final vac = extra['vacancies'];
      if (interested != null && vac != null) {
        hiringLine = '$interested interested · $vac vacancies';
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: nested ? 8 : 12),
      child: GxPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: nested ? context.gx.card2 : context.gx.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gx.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _categoryBadge(context, category),
                  const Spacer(),
                  Text(
                    status.replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: nested ? 14 : 16,
                  fontWeight: FontWeight.w800,
                  color: context.gx.ink,
                ),
              ),
              if (role.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.gx.accent,
                  ),
                ),
              ],
              if (counterparty != null && counterparty.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  counterparty,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.6),
                  ),
                ),
              ],
              if (hiringLine != null) ...[
                const SizedBox(height: 4),
                Text(
                  hiringLine,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
              if (when != null) ...[
                const SizedBox(height: 6),
                Text(
                  when,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.gx.ink.withValues(alpha: 0.45),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'View details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.gx.accentSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryBadge(BuildContext context, String category) {
    final label = switch (category) {
      'services' => 'Services',
      'rentals' => 'Rentals',
      'events' => 'Events',
      'job_applications' => 'Job Applications',
      'hiring' => 'Hiring',
      _ => 'Activity',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.gx.card2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: context.gx.ink.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
