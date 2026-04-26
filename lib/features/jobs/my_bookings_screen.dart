import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/booking_repository.dart';
import 'booking_detail_screen.dart';
import '../../repositories/auth_repository.dart';
import '../booking/arrival_otp_screen.dart';
import '../booking/completion_otp_screen.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  // Pagination state per tab
  final Map<String, List<dynamic>> _paginatedData = {'COMPLETED': [], 'CANCELLED': []};
  final Map<String, int> _currentPage = {'COMPLETED': 1, 'CANCELLED': 1};
  final Map<String, bool> _hasMore = {'COMPLETED': true, 'CANCELLED': true};
  final Map<String, bool> _isLoadingMore = {'COMPLETED': false, 'CANCELLED': false};
  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tab = ['ACTIVE', 'COMPLETED', 'CANCELLED'][_tabController.index];
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
      final status = tab == 'CANCELLED' ? 'CANCELLED' : 'COMPLETED';
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

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(myBookingsProvider);
              // Reset paginated tabs
              for (final tab in ['COMPLETED', 'CANCELLED']) {
                _paginatedData[tab] = [];
                _currentPage[tab] = 1;
                _hasMore[tab] = true;
              }
              // Reload current tab if needed
              final idx = _tabController.index;
              final tabName = ['ACTIVE', 'COMPLETED', 'CANCELLED'][idx];
              if (tabName != 'ACTIVE') _loadPage(tabName, reset: true);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Active tab — uses the shared provider (small dataset, no pagination needed)
          bookingsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (bookings) => _buildActiveList(context, ref, bookings),
          ),
          // Completed tab — paginated
          _buildPaginatedList(context, ref, 'COMPLETED'),
          // Cancelled tab — paginated
          _buildPaginatedList(context, ref, 'CANCELLED'),
        ],
      ),
    );
  }

  // ── Active Bookings (no pagination, small dataset) ─────────
  Widget _buildActiveList(BuildContext context, WidgetRef ref, List<dynamic> bookings) {
    final filtered = bookings.where((b) {
      final bStatus = (b['status'] ?? '').toString().toUpperCase();
      return ['REQUESTED', 'CUSTOM_REQUESTED', 'PENDING', 'ACCEPTED', 'CONFIRMED', 'ACTIVE', 'IN_PROGRESS'].contains(bStatus);
    }).toList();

    if (filtered.isEmpty) return _buildEmptyState('active');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildBookingCard(context, ref, filtered[index], 'ACTIVE'),
    );
  }

  // ── Paginated Bookings (Completed / Cancelled) ─────────────
  Widget _buildPaginatedList(BuildContext context, WidgetRef ref, String tab) {
    final items = _paginatedData[tab]!;
    final loading = _isLoadingMore[tab] == true;
    final hasMore = _hasMore[tab] == true;

    if (items.isEmpty && !loading) {
      // Trigger initial load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_paginatedData[tab]!.isEmpty && _hasMore[tab] == true) {
          _loadPage(tab);
        }
      });
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty && loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 && hasMore && !loading) {
          _loadPage(tab);
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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
    );
  }

  Widget _buildEmptyState(String tab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(
            'No $tab bookings found',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ── Shared Booking Card ────────────────────────────────────
  Widget _buildBookingCard(BuildContext context, WidgetRef ref, dynamic booking, String tab) {
    final scheduledAt = booking['scheduledAt'] != null
        ? DateTime.parse(booking['scheduledAt'])
        : DateTime.now();
    final displayUser = booking['operator'] ?? booking['customer'] ?? {};
    final userName = displayUser['name'] ?? 'Booking #${booking['id']?.toString().substring(0, 5)}';
    final userImg = displayUser['profileImageUrl'] ?? 'https://i.pravatar.cc/150?u=${booking['id']}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(userImg),
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        booking['serviceName'] ?? 'General Service',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge((booking['status'] ?? 'PENDING').toString().toUpperCase()),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date & Time',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      DateFormat('MMM d, yyyy - hh:mm a').format(scheduledAt),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tab == 'ACTIVE' ? 'Estimated' : 'Total Paid',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '₹${booking['amount'] ?? 0}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingDetailScreen(booking: booking),
                        ),
                      );
                      ref.invalidate(myBookingsProvider);
                    },
                    child: const Text('Details'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final user = ref.read(currentUserProvider).value;
                      final isOperator = user?.id == (booking['operator']?['id'] ?? booking['operator']);
                      
                      return ElevatedButton(
                        onPressed: () async {
                           final bStatus = (booking['status'] ?? '').toString().toUpperCase();
                           
                           if (bStatus == 'ACCEPTED' || bStatus == 'ARRIVED') {
                             final otp = booking['arrivalOtp']?.toString();
                             if (otp == null || otp.isEmpty) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text('Verification code is not generated yet. Please wait...')),
                               );
                               return;
                             }
                             await Navigator.push(
                               context,
                               MaterialPageRoute(
                                 builder: (_) => ArrivalOtpScreen(
                                   bookingId: booking['id'],
                                   workerName: booking['operator']?['name'] ?? 'Worker',
                                   arrivalOtp: otp,
                                   isWorker: isOperator,
                                 ),
                               ),
                             );
                           } else if (bStatus == 'ACTIVE' || bStatus == 'IN_PROGRESS') {
                             await Navigator.push(
                               context,
                               MaterialPageRoute(
                                 builder: (_) => CompletionOtpScreen(
                                   bookingId: booking['id'],
                                   workerName: booking['operator']?['name'] ?? 'Worker',
                                   isWorker: isOperator,
                                 ),
                               ),
                             );
                           } else {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: booking)),
                              );
                           }
                           // Refresh bookings after returning from any sub-screen
                           ref.invalidate(myBookingsProvider);
                        },
                        child: Text(tab == 'ACTIVE' ? 'Open Tracker' : 'Rebook'),
                      );
                    }
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toUpperCase()) {
      case 'REQUESTED':
        color = Colors.orange;
        break;
      case 'ACCEPTED':
        color = Colors.blue;
        break;
      case 'IN_PROGRESS':
        color = Colors.indigo;
        break;
      case 'COMPLETED':
        color = Colors.green;
        break;
      case 'CANCELLED':
      case 'REJECTED':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
