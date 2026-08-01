import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/models/worker.dart';
import '../../shared/widgets/glass_container.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../repositories/favourites_repository.dart';
import '../booking/instant_request_screen.dart';
import '../messages/chat_thread_screen.dart';

class WorkerDetailScreen extends StatelessWidget {
  final Worker worker;
  final bool isInstant;

  const WorkerDetailScreen({super.key, required this.worker, this.isInstant = true});

  /// Dependency-free "share": copies a readable profile summary to the
  /// clipboard (no share_plus dep) and confirms via the app snackbar.
  void _shareProfile(BuildContext context) {
    final text = '${worker.name} — ${worker.title} on Gixbee\n'
        '⭐ ${worker.rating.toStringAsFixed(1)} · '
        '${worker.completedJobs} jobs done · '
        '₹${worker.hourlyRate.toStringAsFixed(0)}/hr';
    Clipboard.setData(ClipboardData(text: text));
    showGxSnack(context, 'Profile copied — share it anywhere',
        type: GxSnackType.success);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Amazon-Style Image Header
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'worker-${worker.id}',
                child: Image.network(
                  worker.imageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => Container(
                    color: colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person, size: 64),
                  ),
                ),
              ),
            ),
            actions: [
              CircleAvatar(
                backgroundColor: Colors.black26,
                child: IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: () => _shareProfile(context),
                ),
              ),
              const SizedBox(width: 8),
              _FavouriteButton(workerId: worker.id),
              const SizedBox(width: 16),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              worker.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: colorScheme.secondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            // Real straight-line distance from /workers/nearby
                            // (haversine). Hidden when the backend didn't supply
                            // it (e.g. reached without a selected location).
                            if (worker.distanceKm != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.near_me_rounded,
                                      size: 14,
                                      color: context.gx.accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${worker.distanceKm!.toStringAsFixed(1)} km away',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                worker.rating.toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          Text(
                            '${worker.reviewCount} reviews',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Pricing
                  Row(
                    children: [
                      Text(
                        '₹${worker.hourlyRate.toInt()}',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: context.gx.accent,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'per hour',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Availability Tags
                  if (worker.availabilityTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      children: worker.availabilityTags
                          .map((tag) => Chip(
                                label: Text(tag),
                                backgroundColor: colorScheme.secondaryContainer
                                    .withValues(alpha: 0.3),
                                labelStyle:
                                    TextStyle(color: colorScheme.secondary),
                                side: BorderSide.none,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Bio / About
                  Text(
                    'About this Professional',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    worker.bio,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Skills
                  Text(
                    'Skills & Expertise',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: worker.skills
                        .map((skill) => GlassContainer(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              opacity: 0.1,
                              child: Text(
                                skill,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ))
                        .toList(),
                  ),

                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: GxButton(
                label: 'Chat Now',
                filled: false,
                height: 52,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatThreadScreen(
                        otherUserId: worker.id,
                        otherUserName: worker.name,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Builder(
                builder: (context) {
                  final available = worker.status == 'available';
                  return GxPressable(
                    onTap: available ? () => _startBooking(context) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: available
                            ? const LinearGradient(
                                colors: GixbeeTheme.purpleGradient,
                              )
                            : null,
                        color: available ? null : Colors.grey,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        available ? 'Request this service' : 'Worker is Busy',
                        style: TextStyle(
                          color: context.gx.onAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startBooking(BuildContext context) async {
    // Uber/Grab model (user decision 2026-07-04): NO direct person booking.
    // Even from a pro's profile (e.g. saved vendors), the CTA opens the
    // broadcast request for this pro's service — all nearby live pros are
    // notified and the first to accept is assigned.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InstantRequestScreen(
          skill: worker.skills.isNotEmpty ? worker.skills.first : worker.title,
          suggestedRate: worker.hourlyRate,
        ),
      ),
    );
  }
}

/// Save-to-favourites toggle in the header. Loads the persisted state from
/// `/favourites/:workerId` on mount, then flips optimistically on tap and calls
/// the backend (POST to add / DELETE to remove), reverting if the call fails.
class _FavouriteButton extends ConsumerStatefulWidget {
  final String workerId;
  const _FavouriteButton({required this.workerId});

  @override
  ConsumerState<_FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends ConsumerState<_FavouriteButton> {
  bool _isFav = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final fav = await ref
          .read(favouritesRepositoryProvider)
          .isFavourite(widget.workerId);
      if (mounted) setState(() => _isFav = fav);
    } catch (_) {
      // Silent: unauthenticated or offline — default to not-favourited.
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final wasFav = _isFav;
    setState(() {
      _isFav = !wasFav;
      _busy = true;
    });
    try {
      final repo = ref.read(favouritesRepositoryProvider);
      if (wasFav) {
        await repo.remove(widget.workerId);
      } else {
        await repo.add(widget.workerId);
      }
      if (mounted) {
        showGxSnack(
          context,
          wasFav ? 'Removed from favourites' : 'Saved to favourites',
          type: GxSnackType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isFav = wasFav); // revert
        showGxSnack(context, 'Could not update favourites',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.black26,
      child: IconButton(
        tooltip: _isFav ? 'Remove from favourites' : 'Save to favourites',
        icon: Icon(
          _isFav ? Icons.favorite : Icons.favorite_border,
          color: _isFav ? context.gx.accent : context.gx.onAccent,
        ),
        onPressed: _busy ? null : _toggle,
      ),
    );
  }
}
