import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';
import '../../repositories/booking_repository.dart';
import 'booking_detail_screen.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_fade.dart';

/// Gixbee v106 — Grab "Activity" pattern: segmented pill tabs, timeline-style
/// booking cards, pull-to-refresh, skeleton loading. Migrated to the v106
/// purple-primary accent system (active pill + primary CTAs + service icon now
/// violet; status badges use the v106 accent palette). Logic (pagination, OTP
/// routing, providers) is unchanged from the pre-redesign screen.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _segment = 0;

  static const List<String> _tabNames = ['UPCOMING', 'ACTIVE', 'PAST'];
  static const List<String> _tabLabels = ['Upcoming', 'Active', 'Past'];

  // Pagination state per tab
  final Map<String, List<dynamic>> _paginatedData = {'UPCOMING': [], 'PAST': []};
  final Map<String, int> _currentPage = {'UPCOMING': 1, 'PAST': 1};
  final Map<String, bool> _hasMore = {'UPCOMING': true, 'PAST': true};
  final Map<String, bool> _isLoadingMore = {'UPCOMING': false, 'PAST': false};
  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      // Keep the segmented pill in sync for both taps and swipes.
      if (_segment != _tabController.index) {
        setState(() => _segment = _tabController.index);
      }
      if (!_tabController.indexIsChanging) {
        final tab = _tabNames[_tabController.index];
        if (tab != 'ACTIVE' && _paginatedData[tab]!.isEmpty) {
          _loadPage(tab);
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPage(String tab, {bool reset = false}) async {
    if (_isLoadingMore[tab] == true) return;
    if (!reset && _hasMore[tab] == false) return;

    setState(() => _isLoadingMore[tab] = true);

    if (reset) {
      _currentPage[tab] = 1;
      _paginatedData[tab] = [];
      _hasMore[tab] = true;
    }

    try {
      final repo = ref.read(bookingRepositoryProvider);
      final status = tab == 'PAST' ? 'COMPLETED' : tab == 'UPCOMING' ? 'PENDING' : 'ACTIVE';
      final results = await repo.getMyBookings(
        status: status,
        page: _currentPage[tab]!,
        limit: _pageSize,
      );

      if (mounted) {
        setState(() {
          _paginatedData[tab]!.addAll(results);
          _hasMore[tab] = results.length >= _pageSize;
          _currentPage[tab] = _currentPage[tab]! + 1;
          _isLoadingMore[tab] = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore[tab] = false);
    }
  }

  void _refreshAll() {
    ref.invalidate(myBookingsProvider);
    for (final tab in ['UPCOMING', 'PAST']) {
      _paginatedData[tab] = [];
      _currentPage[tab] = 1;
      _hasMore[tab] = true;
    }
    final tabName = _tabNames[_tabController.index];
    if (tabName != 'ACTIVE') _loadPage(tabName, reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        backgroundColor: context.gx.bg,
        elevation: 0,
        title: Text(
          'My Bookings',
          style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w800),
        ),
        iconTheme: IconThemeData(color: context.gx.ink),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh, color: context.gx.ink.withValues(alpha: 0.7)),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSegmentedControl(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Active tab — shared provider (small dataset, no pagination)
                RefreshIndicator(
                  color: GixbeeTheme.accentViolet,
                  onRefresh: () async {
                    ref.invalidate(myBookingsProvider);
                    await ref.read(myBookingsProvider.future);
                  },
                  child: GxFade(
                    child: KeyedSubtree(
                      key: ValueKey(bookingsAsync.maybeWhen(
                        data: (_) => 'data',
                        error: (_, __) => 'error',
                        orElse: () => 'loading',
                      )),
                      child: bookingsAsync.when(
                        loading: () => _buildSkeletonList(),
                        error: (err, _) => _buildErrorList('$err'),
                        data: (bookings) =>
                            _buildActiveList(context, ref, bookings),
                      ),
                    ),
                  ),
                ),
                // Upcoming / Past — paginated
                _buildPaginatedList(context, ref, 'UPCOMING'),
                _buildPaginatedList(context, ref, 'PAST'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented pill control (v126 design) ─────
  Widget _buildSegmentedControl() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.gx.card2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final selected = _segment == i;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tabController.animateTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? GixbeeTheme.accentViolet : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  _tabLabels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? context.gx.onAccent : context.gx.ink.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Skeleton list while loading ────────────────────────────
  Widget _buildSkeletonList() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) =>
          const GxSkeleton(width: double.infinity, height: 132, radius: 16),
    );
  }

  Widget _buildErrorList(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.cloud_off_outlined,
            size: 56, color: context.gx.ink.withValues(alpha: 0.25)),
        const SizedBox(height: 16),
        Text(
          'Could not load bookings\n$message',
          textAlign: TextAlign.center,
          style: const TextStyle(color: GixbeeTheme.textMed, fontSize: 13),
        ),
      ],
    );
  }

  // ── Active Bookings (no pagination, small dataset) ─────────
  Widget _buildActiveList(BuildContext context, WidgetRef ref, List<dynamic> bookings) {
    final filtered = bookings.where((b) {
      final bStatus = (b['status'] ?? '').toString().toUpperCase();
      // ARRIVED added (Pass 10): backend treats it as mid-job (dispatch guard)
      // and active_booking_card includes it — this set was the only one missing it.
      return ['REQUESTED', 'CUSTOM_REQUESTED', 'PENDING', 'ACCEPTED', 'CONFIRMED', 'ARRIVED', 'ACTIVE', 'IN_PROGRESS'].contains(bStatus);
    }).toList();

    if (filtered.isEmpty) return _buildEmptyState('active');

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: filtered.length,
      itemBuilder: (context, index) =>
          _buildBookingCard(context, ref, filtered[index], 'ACTIVE'),
    );
  }

  // ── Paginated Bookings (Completed / Cancelled) ─────────────
  Widget _buildPaginatedList(BuildContext context, WidgetRef ref, String tab) {
    final items = _paginatedData[tab]!;
    final loading = _isLoadingMore[tab] == true;
    final hasMore = _hasMore[tab] == true;

    if (items.isEmpty && !loading) {
      if (hasMore) {
        // Trigger initial load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_paginatedData[tab]!.isEmpty && _hasMore[tab] == true) {
            _loadPage(tab);
          }
        });
        return _buildSkeletonList();
      }
      // Loaded once, zero results.
      return RefreshIndicator(
        color: GixbeeTheme.accentViolet,
        onRefresh: () => _loadPage(tab, reset: true),
        child: _buildEmptyState(tab.toLowerCase()),
      );
    }

    if (items.isEmpty && loading) {
      return _buildSkeletonList();
    }

    return RefreshIndicator(
      color: GixbeeTheme.accentViolet,
      onRefresh: () => _loadPage(tab, reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 && hasMore && !loading) {
            _loadPage(tab);
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: items.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return _buildBookingCard(context, ref, items[index], tab);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(String tab) {
    // ListView so RefreshIndicator still works on an empty tab.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        Icon(Icons.receipt_long_outlined,
            size: 64, color: GixbeeTheme.accentViolet.withValues(alpha: 0.35)),
        const SizedBox(height: 16),
        Text(
          'No $tab bookings found',
          textAlign: TextAlign.center,
          style: const TextStyle(color: GixbeeTheme.textMed, fontSize: 15),
        ),
      ],
    );
  }

  // ── v126 Booking Card ────────────────────────────
  Widget _buildBookingCard(BuildContext context, WidgetRef ref, dynamic booking, String tab) {
    final scheduledAt = booking['scheduledAt'] != null
        ? DateTime.parse(booking['scheduledAt'])
        : DateTime.now();
    final displayUser = booking['operator'] ?? booking['customer'] ?? {};
    final bookingId = booking['id']?.toString() ?? '';
    final shortId = '#BK-${bookingId.length > 5 ? bookingId.substring(0, 5) : bookingId}';
    final userName = displayUser['name'] ?? 'Guest User';
    final serviceName = (booking['skill'] ?? booking['serviceName'] ?? 'General Service').toString();
    final amount = num.tryParse('${booking['totalAmount'] ?? booking['amount'] ?? 0}') ?? 0;
    final status = (booking['status'] ?? 'PENDING').toString().toUpperCase();

    Future<void> openDetails() async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(booking: booking),
        ),
      );
      ref.invalidate(myBookingsProvider);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GxPressable(
        onTap: openDetails,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.gx.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.gx.border, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Head
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.gx.card2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(shortId, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF666666))),
                  ),
                  _buildStatusBadge(status),
                ],
              ),
              const SizedBox(height: 10),
              
              // Title
              Text(
                serviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.gx.ink),
              ),
              const SizedBox(height: 4),
              
              // Provider / User
              Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 14, color: GixbeeTheme.accentViolet),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              Container(height: 1, color: context.gx.border),
              const SizedBox(height: 12),
              
              // Bottom row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Date & Time', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d MMM yyyy, hh:mm a').format(scheduledAt),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.gx.ink),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Amount', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                      const SizedBox(height: 4),
                      Text(
                        '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: GixbeeTheme.accentGold),
                      ),
                    ],
                  ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toUpperCase()) {
      case 'REQUESTED':
      case 'CUSTOM_REQUESTED':
      case 'PENDING':
        color = GixbeeTheme.accentGold;
        break;
      case 'ACCEPTED':
      case 'CONFIRMED':
      case 'ARRIVED':
        color = GixbeeTheme.accentBlue;
        break;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        color = GixbeeTheme.accentViolet;
        break;
      case 'COMPLETED':
        color = GixbeeTheme.accentGreen;
        break;
      case 'CANCELLED':
      case 'REJECTED':
        color = const Color(0xFFEF4444);
        break;
      default:
        color = GixbeeTheme.textMed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5),
      ),
    );
  }
}
