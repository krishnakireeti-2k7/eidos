import 'dart:async';
import 'package:eidos/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.createdAt,
  });
}

class ChatController extends StateNotifier<AsyncValue<List<ChatMessage>>> {
  ChatController(this.ref, this.chatId) : super(const AsyncValue.data([])) {
    debugPrint('ChatController: Initializing for chatId: $chatId');
    fetchMessages();
    _listenToMessages();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint('ChatController: Auth state changed: ${data.event}');
      _sub?.cancel();
      fetchMessages();
      _listenToMessages();
    });
  }

  final Ref ref;
  final String chatId;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void dispose() {
    debugPrint('ChatController: Disposing chatId: $chatId');
    _sub?.cancel();
    super.dispose();
  }

  Future<void> fetchMessages() async {
    debugPrint('ChatController: Fetching messages for chatId: $chatId...');
    state = const AsyncValue.loading();
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final response = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);

      final List<ChatMessage> messages =
          (response as List<dynamic>).map((data) {
            return ChatMessage(
              id: data['id'].toString(),
              content: (data['content'] ?? '').toString(),
              isUser: data['user_id'] == userId,
              createdAt: DateTime.parse(
                data['created_at'] ?? DateTime.now().toIso8601String(),
              ),
            );
          }).toList();

      debugPrint('ChatController: Fetched ${messages.length} messages');
      state = AsyncValue.data(messages);
    } catch (e, st) {
      debugPrint('ChatController: Fetch messages error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> sendMessage(String message) async {
    debugPrint('ChatController: Sending message: $message');

    final current = state.value ?? <ChatMessage>[];
    final local = ChatMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      content: message,
      isUser: true,
      createdAt: DateTime.now(),
    );

    state = AsyncValue.data([...current, local]);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final insertResponse =
          await Supabase.instance.client
              .from('messages')
              .insert({
                'chat_id': chatId,
                'user_id': userId,
                'content': message,
                'is_user': true,
              })
              .select()
              .single();

      final insertedMessage = ChatMessage(
        id: insertResponse['id'].toString(),
        content: insertResponse['content'],
        isUser: true,
        createdAt: DateTime.parse(insertResponse['created_at']),
      );

      final updated =
          state.value!
              .map((m) => m.id == local.id ? insertedMessage : m)
              .toList();

      state = AsyncValue.data(updated);

      // Call API service for assistant reply
      final apiService = ref.read(apiServiceProvider);
      final reply = await apiService.sendMessage(
        message,
        userId: userId,
        chatId: chatId,
        requireAuth: true,
      );

      debugPrint('ChatController: ApiService reply: $reply');

      final assistant = ChatMessage(
        id: 'assistant-${DateTime.now().millisecondsSinceEpoch}',
        content: reply,
        isUser: false,
        createdAt: DateTime.now(),
      );

      final finalList =
          [...(state.value ?? <ChatMessage>[])]
            ..add(assistant)
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      state = AsyncValue.data(finalList);
    } catch (e, st) {
      debugPrint('ChatController: Send message error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  void _listenToMessages() {
    debugPrint('ChatController: Starting message stream for chatId: $chatId');

    _sub?.cancel();
    final userId = Supabase.instance.client.auth.currentUser?.id;

    final stream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at');

    _sub = stream.listen(
      (data) {
        final streamed =
            data.map((item) {
              return ChatMessage(
                id: item['id'].toString(),
                content: (item['content'] ?? '').toString(),
                isUser: item['user_id'] == userId,
                createdAt: DateTime.parse(
                  item['created_at'] ?? DateTime.now().toIso8601String(),
                ),
              );
            }).toList();

        final current = state.value ?? <ChatMessage>[];
        final merged = [
          ...current,
          ...streamed.where((m) => !current.any((c) => c.id == m.id)),
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        debugPrint(
          'ChatController: Streamed ${streamed.length} messages, total ${merged.length}',
        );
        state = AsyncValue.data(merged);
      },
      onError: (error, stackTrace) {
        debugPrint('ChatController: Stream error: $error');
        state = AsyncValue.error(error, stackTrace);
      },
    );
  }
}

final chatControllerProvider = StateNotifierProvider.family<
  ChatController,
  AsyncValue<List<ChatMessage>>,
  String
>((ref, chatId) {
  debugPrint(
    'ChatControllerProvider: Creating new ChatController for chatId: $chatId',
  );
  return ChatController(ref, chatId);
});
