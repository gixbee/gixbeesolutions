import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../jobs/pro_skill_provider.dart';
import '../jobs/pro_skill_taxonomy.dart';
import 'instant_request_screen.dart';

/// Uber/Grab-style Instant Help entry: the customer picks a SERVICE, never a
/// person. Tapping a trade goes straight to the request screen (issues +
/// address + budget) and the request is broadcast to all nearby live pros —
/// first to accept is assigned. Trades come from the PRO_TRADE master
/// (admin-managed), with the static taxonomy as offline fallback.
class InstantHelpScreen extends ConsumerWidget {
  const InstantHelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tradesAsync = ref.watch(proTradesProvider);
    final address = ref.watch(currentAddressProvider);

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Instant Help',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text('What do you need help with?',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: context.gx.ink)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 14, color: context.gx.accentSoft),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: context.gx.ink.withValues(alpha: 0.55)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tradesAsync.when(
                  loading: () => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.55),
                    itemCount: 6,
                    itemBuilder: (_, __) => const GxSkeleton(
                        width: double.infinity,
                        height: double.infinity,
                        radius: 18),
                  ),
                  error: (_, __) => _grid(context, kProTrades),
                  data: (trades) =>
                      _grid(context, trades.isEmpty ? kProTrades : trades),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<ProTrade> trades) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: trades.length,
      itemBuilder: (context, i) {
        final t = trades[i];
        return GxPressable(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InstantRequestScreen(
                  skill: t.name,
                  issueOptions: t.subSkills,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.gx.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.gx.border, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: context.gx.accentSoft.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(t.icon,
                      color: context.gx.accentSoft, size: 20),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: context.gx.ink)),
                    const SizedBox(height: 2),
                    Text('At your door in 15–45 min',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: context.gx.ink.withValues(alpha: 0.45))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
