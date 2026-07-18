import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import 'home_sections.dart';

class TodaysOffersScreen extends ConsumerStatefulWidget {
  const TodaysOffersScreen({super.key});

  @override
  ConsumerState<TodaysOffersScreen> createState() => _TodaysOffersScreenState();
}

class _TodaysOffersScreenState extends ConsumerState<TodaysOffersScreen> {
  String _selectedTab = 'All';

  final List<String> _tabs = [
    'All',
    '💍 Jewellery',
    '🥻 Textiles',
    '💆 Beauty',
    '👗 Bridal',
    '📱 Electronics',
    '🛋 Furniture',
    '👓 Opticals',
    '🏋 Fitness',
    '🦷 Dental'
  ];

  @override
  Widget build(BuildContext context) {
    final dealsAsync = ref.watch(dealsProvider);
    
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.gx.ink),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Today's Offers",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.gx.card2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.gx.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_rounded, size: 14, color: context.gx.accentSoft),
                        const SizedBox(width: 4),
                        Text('All Thrissur', style: TextStyle(fontSize: 12, color: context.gx.ink)),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: context.gx.ink.withValues(alpha: 0.54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Tabs
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tab = _tabs[index];
                  final isSelected = tab == _selectedTab;
                  return GxPressable(
                    onTap: () {
                      setState(() {
                        _selectedTab = tab;
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : context.gx.card2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.white : context.gx.border,
                        ),
                      ),
                      child: Text(
                        tab,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.black : context.gx.ink,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // List
            Expanded(
              child: dealsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Failed to load offers')),
                data: (deals) {
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: deals.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final deal = deals[index];
                      return _OfferListItem(deal: deal);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferListItem extends StatelessWidget {
  final DealEntry deal;
  const _OfferListItem({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GxPressable(
      onTap: () {
        showGxSheet(
          context,
          title: 'Claimed from',
          child: ClaimDealSheet(deal: deal),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.gx.card2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.gx.border),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: context.gx.accentSoft.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_offer_rounded, color: context.gx.accentSoft, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.subtitle ?? 'Gixbee Partner',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.gx.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deal.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: GixbeeTheme.accentGold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
