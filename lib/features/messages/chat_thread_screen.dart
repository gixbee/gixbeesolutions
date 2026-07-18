import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/auth_repository.dart';
import '../../repositories/chat_repository.dart';
import '../../services/socket_service.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// One-to-one chat thread. Reachable from the inbox or from a booking
/// (pass [bookingId] to tag the conversation with its booking).
/// Gixbee 2026 reskin: neutral header, date separators, glass composer
/// docked with blur. v106 (2026-06-15): purple-primary accents — violet
/// avatar tint + focus ring, accentPurple "mine" bubble + send button
/// (orange kept only for the wordmark/auth, per gixbee-v106-redesign).
class ChatThreadScreen extends ConsumerStatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? bookingId;

  const ChatThreadScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.bookingId,
  });

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _sub;

  bool _loading = true;
  bool _sending = false;
  String? _myId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _sub = ref.read(socketServiceProvider).messages.listen(_onIncoming);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = await ref.read(currentUserProvider.future);
    final thread =
        await ref.read(chatRepositoryProvider).getThread(widget.otherUserId);
    if (!mounted) return;
    setState(() {
      _myId = user?.id;
      _messages
        ..clear()
        ..addAll(thread);
      _loading = false;
    });
    _scrollToBottom();
    ref.invalidate(conversationsProvider); // thread read clears unread badge
  }

  void _onIncoming(Map<String, dynamic> data) {
    if (!mounted) return;
    final msg = ChatMessage.fromMap(data);
    // Only messages belonging to this thread
    final inThread = msg.senderId == widget.otherUserId ||
        msg.recipientId == widget.otherUserId;
    if (!inThread) return;
    if (_messages.any((m) => m.id == msg.id)) return;
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      final sent = await ref.read(chatRepositoryProvider).sendMessage(
            recipientId: widget.otherUserId,
            body: text,
            bookingId: widget.bookingId,
          );
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == sent.id)) _messages.add(sent);
      });
      _scrollToBottom();
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (mounted) {
        _input.text = text; // restore so the user can retry
        showGxSnack(context, 'Message failed to send',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Date separator helpers ────────────────────────────────────────────────

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final month = _months[t.month - 1];
    return t.year == now.year ? '${t.day} $month' : '${t.day} $month ${t.year}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: scheme.surface,
        leading: Center(
          child: GxPressable(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(9),
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
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.gx.accentSoft.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.otherUserName.isNotEmpty
                    ? widget.otherUserName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: context.gx.accentSoft,
                    fontWeight: FontWeight.w900,
                    fontSize: 15),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUserName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.gx.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text('Say hello 👋',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final showDate = i == 0 ||
                              !_sameDay(
                                  _messages[i - 1].createdAt, m.createdAt);
                          return Column(
                            children: [
                              if (showDate) _dateSeparator(scheme, m.createdAt),
                              _bubble(scheme, m),
                            ],
                          );
                        },
                      ),
          ),
          _composer(scheme),
        ],
      ),
    );
  }

  Widget _dateSeparator(ColorScheme scheme, DateTime t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.3),
                endIndent: 12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.gx.ink.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: context.gx.ink.withValues(alpha: 0.10)),
            ),
            child: Text(
              _dayLabel(t).toUpperCase(),
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.3),
                indent: 12),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ColorScheme scheme, ChatMessage m) {
    final mine = m.senderId == _myId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? context.gx.accent : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Text(
          m.body,
          style: TextStyle(
            color: mine ? context.gx.onAccent : scheme.onSurface,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // ── Glass composer docked with blur ──────────────────────────────────────
  Widget _composer(ColorScheme scheme) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: context.gx.card2.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                  color: context.gx.ink.withValues(alpha: 0.10)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        filled: true,
                        fillColor: context.gx.ink.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                              color: context.gx.ink.withValues(alpha: 0.10)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                              color: context.gx.ink.withValues(alpha: 0.10)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                              color: context.gx.accentSoft),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: context.gx.accent,
                      foregroundColor: context.gx.onAccent,
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.gx.onAccent),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
