import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme_provider.dart';
import '../jobs/offers_screen.dart';
import '../../services/location_service.dart';
import '../booking/book_services_split_screen.dart';
import '../jobs/find_job_module.dart';
import '../business/list_business_type_screen.dart';
import '../../shared/widgets/dribbble_background.dart';
import 'home_carousel.dart';
import '../jobs/register_pro_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine dynamic theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: DribbbleBackground(
        child: SafeArea(
          child: CustomScrollView(
              slivers: [
                // GLASS Header
                SliverToBoxAdapter(
                  child: _buildModernHeader(context, ref, isDark),
                ),

                // AMAZON STYLE CATEGORIES
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildAmazonCategoryRow(context),
                  ),
                ),
                
                // CAROUSEL
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: HomeCarousel(),
                  ),
                ),

                // FOR YOU
                SliverToBoxAdapter(
                  child: _buildSectionTitle(context, 'For You'),
                ),
                SliverToBoxAdapter(
                  child: _buildScrollableCards(context),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
    );
  }

  // ──────────────────────────────────────────
  // MODERN GLASS HEADER
  // ──────────────────────────────────────────
  Widget _buildModernHeader(BuildContext context, WidgetRef ref, bool isDark) {
    final address = ref.watch(currentAddressProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location 
          Row(
            children: [
              Icon(Icons.location_on_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  address,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                onPressed: () {
                  ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Floating Search Bar
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Find professionals...',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                  ),
                ),
                Icon(Icons.mic_rounded, color: colorScheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildAmazonCategoryRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Categories List
    final List<Map<String, dynamic>> categories = [
      {
        'title': 'Register',
        'icon': Icons.assignment_ind_rounded,
        'color': colorScheme.primary, // Using primary color to make it pop
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterProScreen())),
      },
      {
        'title': 'Services',
        'icon': Icons.bolt_rounded,
        'color': colorScheme.primaryContainer,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookServicesSplitScreen())),
      },
      {
        'title': 'Jobs',
        'icon': Icons.work_rounded,
        'color': colorScheme.secondaryContainer,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FindJobModule())),
      },
      {
        'title': 'Business',
        'icon': Icons.store_rounded,
        'color': colorScheme.tertiaryContainer,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListBusinessTypeScreen())),
      },
      {
        'title': 'Offers',
        'icon': Icons.local_offer_rounded,
        'color': colorScheme.errorContainer,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen())),
      },
      {
        'title': 'Rentals',
        'icon': Icons.category_rounded,
        'color': colorScheme.surfaceContainerHighest,
        'onTap': () {},
      },
    ];

    return SizedBox(
      height: 100,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return _buildAmazonCategoryItem(
            context: context,
            title: cat['title'],
            icon: cat['icon'],
            bgColor: cat['color'],
            onTap: cat['onTap'],
          );
        },
      ),
    );
  }

  Widget _buildAmazonCategoryItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: colorScheme.onSurface, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // SOFT OVERLAPPING SCROLL CARDS
  // ──────────────────────────────────────────
  // Issue #7, #26: Promotional card data extracted from widget code.
  // Replace with a backend fetch (e.g. GET /content/home-cards) when ready.
  static const List<Map<String, String>> _promoCards = [
    {
      'title': 'Home Cleaning',
      'subtitle': 'Top rated pros',
      'imageUrl': 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?q=80&w=2070&auto=format&fit=crop',
    },
    {
      'title': 'Plumbing Fixes',
      'subtitle': 'Under 30 mins',
      'imageUrl': 'https://images.unsplash.com/photo-1585704032915-c3400ca199e7?q=80&w=2070&auto=format&fit=crop',
    },
  ];

  Widget _buildScrollableCards(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _promoCards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final card = _promoCards[index];
          return _buildInfoCard(
            context,
            card['title']!,
            card['subtitle']!,
            card['imageUrl']!,
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, String subtitle, String imageUrl) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(imageUrl, fit: BoxFit.cover),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

