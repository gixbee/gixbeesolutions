import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/chat_repository.dart';
import '../../services/socket_service.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_fade.dart';
import '../../theme.dart';
import 'chat_thread_screen.dart';

/// Inbox — one row per conversation partner. Refreshes when a `new_message`
/// arrives over the socket.
/// Gixbee 2026 reskin: neutral header + search pill, glass rows, skeleton
/// loading. v106 migration (2026-06-15): accent swapped orange→violet to
/// match the purple-primary main app; pink reserved for the unread badge.
class MessagesListScreen extends ConsumerStatefulWidget {
  const MessagesListScreen({super.key});

  @override
  ConsumerState<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends ConsumerState<MessagesListScreen> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _sub = ref.read(socketServiceProvider).messages.listen((_) {
      if (mounted) ref.invalidate(conversationsProvider);
    });
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final convosAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Neutral header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Messages',
                        style: TextStyle(
                            color: context.gx.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                  ),
                  GxPressable(
                    onTap: () => ref.invalidate(conversationsProvider),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.gx.border),
                      ),
                      child: Icon(Icons.refresh_rounded,
                          color: context.gx.ink, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            // ── Search pill ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontSize: 14, color: context.gx.ink),
                decoration: InputDecoration(
                  hintText: 'Search conversations…',
                  hintStyle:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: scheme.onSurfaceVariant),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: scheme.onSurfaceVariant),
                          onPressed: _searchCtrl.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: scheme.surface,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: context.gx.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: context.gx.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide:
                        BorderSide(color: context.gx.accent, width: 1.5),
                  ),
                ),
              ),
            ),

            // ── Conversations ──
            Expanded(
              child: GxFade(
                child: KeyedSubtree(
                  key: ValueKey(convosAsync.maybeWhen(
                    data: (_) => 'data',
                    error: (_, __) => 'error',
                    orElse: () => 'loading',
                  )),
                  child: convosAsync.when(
                loading: () => _skeletonList(),
                error: (e, __) => GxNetworkError(
                  error: e,
                  title: 'Could not load messages',
                  accent: context.gx.accentSoft,
                  onRetry: () => ref.invalidate(conversationsProvider),
                ),
                data: (convos) {
                  final filtered = _query.isEmpty
                      ? convos
                      : convos
                          .where((c) =>
                              c.name.toLowerCase().contains(_query) ||
                              c.lastMessage.toLowerCase().contains(_query))
                          .toList();
                  if (filtered.isEmpty) {
                    return _query.isNotEmpty
                        ? GxEmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No matches',
                            message: 'No conversations match your search.',
                            accent: context.gx.accentSoft,
                          )
                        : GxEmptyState(
                            icon: Icons.forum_outlined,
                            title: 'No messages yet',
                            message:
                                'Chats with vendors and workers will appear here.',
                            accent: context.gx.accentSoft,
                          );
                  }
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(conversationsProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _conversationCard(scheme, filtered[i]),
                    ),
                  );
                },
              ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Glass conversation row ───────────────────────────────────────────────
  Widget _conversationCard(ColorScheme scheme, ChatConversation c) {
    final initial = c.name.isNotEmpty ? c.name[0].toUpperCase() : '?';
    final hasUnread = c.unread > 0;
    // Collapse the compound row (avatar + name + last message + time + unread
    // badge) into ONE screen-reader node so TalkBack/VoiceOver announce it as a
    // single tappable conversation instead of 4–5 separate swipe stops.
    return MergeSemantics(
      child: GxPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            otherUserId: c.userId,
            otherUserName: c.name,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.gx.ink.withValues(alpha: hasUnread ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasUnread
                ? context.gx.accentSoft.withValues(alpha: 0.35)
                : context.gx.ink.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            // Squircle initial avatar (primary tint — no gradient)
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: context.gx.accentSoft.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Text(initial,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: context.gx.accentSoft)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight:
                              hasUnread ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 14.5,
                          color: scheme.onSurface)),
                  const SizedBox(height: 3),
                  Text(c.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: hasUnread
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_ago(c.lastAt),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasUnread
                            ? context.gx.accentSoft
                            : scheme.onSurfaceVariant)),
                SizedBox(height: 5),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: GixbeeTheme.accentPink,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    constraints: const BoxConstraints(minWidth: 20),
                    child: Text('${c.unread}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: context.gx.onAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _skeletonList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const GxSkeleton(
          width: double.infinity, height: 74, radius: 16),
    );
  }
}
