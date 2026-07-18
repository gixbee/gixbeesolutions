import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart'; // dioProvider

final chatRepositoryProvider = Provider((ref) {
  return ChatRepository(ref.watch(dioProvider));
});

/// Inbox list — invalidate after sending or receiving a message.
final conversationsProvider =
    FutureProvider.autoDispose<List<ChatConversation>>((ref) async {
  return ref.watch(chatRepositoryProvider).getConversations();
});

/// Thread with a specific user.
final threadProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, userId) async {
  return ref.watch(chatRepositoryProvider).getThread(userId);
});

class ChatConversation {
  final String userId;
  final String name;
  final String phoneNumber;
  final String lastMessage;
  final DateTime lastAt;
  final int unread;

  ChatConversation({
    required this.userId,
    required this.name,
    required this.phoneNumber,
    required this.lastMessage,
    required this.lastAt,
    required this.unread,
  });

  factory ChatConversation.fromMap(Map<String, dynamic> m) => ChatConversation(
        userId: m['userId']?.toString() ?? '',
        name: (m['name'] ?? 'Gixbee user').toString(),
        phoneNumber: (m['phoneNumber'] ?? '').toString(),
        lastMessage: (m['lastMessage'] ?? '').toString(),
        lastAt: DateTime.tryParse(m['lastAt']?.toString() ?? '') ??
            DateTime.now(),
        unread: (m['unread'] is num) ? (m['unread'] as num).toInt() : 0,
      );
}

class ChatMessage {
  final String id;
  final String body;
  final String? bookingId;
  final bool isRead;
  final DateTime createdAt;
  final String senderId;
  final String recipientId;

  ChatMessage({
    required this.id,
    required this.body,
    required this.bookingId,
    required this.isRead,
    required this.createdAt,
    required this.senderId,
    required this.recipientId,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id']?.toString() ?? '',
        body: (m['body'] ?? '').toString(),
        bookingId: m['bookingId']?.toString(),
        isRead: m['isRead'] == true,
        createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        senderId: m['senderId']?.toString() ?? '',
        recipientId: m['recipientId']?.toString() ?? '',
      );
}

class ChatRepository {
  final Dio _dio;
  ChatRepository(this._dio);

  Future<List<ChatConversation>> getConversations() async {
    try {
      final response = await _dio.get('/messages/conversations');
      final data = response.data as List;
      return data
          .map((e) => ChatConversation.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('GetConversations failed: $e');
      return [];
    }
  }

  Future<List<ChatMessage>> getThread(String userId) async {
    try {
      final response = await _dio.get('/messages/thread/$userId');
      final data = response.data as List;
      return data
          .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('GetThread failed: $e');
      return [];
    }
  }

  Future<ChatMessage> sendMessage({
    required String recipientId,
    required String body,
    String? bookingId,
  }) async {
    final response = await _dio.post('/messages', data: {
      'recipientId': recipientId,
      'body': body,
      if (bookingId != null) 'bookingId': bookingId,
    });
    return ChatMessage.fromMap(Map<String, dynamic>.from(response.data));
  }
}
