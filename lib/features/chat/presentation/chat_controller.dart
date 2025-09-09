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
  ChatController(this.ref) : super(const AsyncValue.data([])) {
    debugPrint('ChatController: Initializing');
    fetchMessages();
    _listenToMessages();
    // Restart stream on auth changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint('ChatController: Auth state changed: ${data.event}');
      _sub?.cancel();
      fetchMessages();
      _listenToMessages();
    });
  }

  final Ref ref;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void dispose() {
    debugPrint('ChatController: Disposing');
    _sub?.cancel();
    super.dispose();
  }

  Future<void> fetchMessages() async {
    debugPrint('ChatController: Fetching messages...');
    state = const AsyncValue.loading();
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ChatController: No user authenticated');
        state = AsyncValue.error(
          Exception('User not authenticated'),
          StackTrace.current,
        );
        return;
      }

      final response =
          await Supabase.instance.client
                  .from('messages')
                  .select()
                  .eq('user_id', userId)
                  .order('created_at', ascending: true)
              as List<dynamic>;

      final List<ChatMessage> messages =
          response.map((data) {
            return ChatMessage(
              id: data['id'].toString(),
              content: (data['content'] ?? '').toString(),
              isUser: data['role'] == 'user', // ✅ FIX
              createdAt: DateTime.parse(
                data['created_at'] ?? DateTime.now().toIso8601String(),
              ),
            );
          }).toList();

      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      debugPrint('ChatController: Fetched ${messages.length} messages');
      state = AsyncValue.data(messages);
    } catch (e, st) {
      debugPrint('ChatController: Fetch messages error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> sendMessage(String message) async {
    debugPrint('ChatController: Sending message: $message');

    // Optimistic update for user message
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

      final apiService = ref.read(apiServiceProvider);
      final reply = await apiService.sendMessage(
        message,
        userId: userId,
        requireAuth: true,
      );

      debugPrint('ChatController: ApiService reply: $reply');

      // Append assistant reply immediately
      final assistant = ChatMessage(
        id: 'assistant-${DateTime.now().millisecondsSinceEpoch}',
        content: reply,
        isUser: false,
        createdAt: DateTime.now(),
      );

      final List<ChatMessage> updated = [...(state.value ?? []), assistant]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      state = AsyncValue.data(updated);
    } catch (e, st) {
      debugPrint('ChatController: Send message error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  void _listenToMessages() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('ChatController: No user ID for streaming');
      state = AsyncValue.error(
        Exception('No user ID for streaming'),
        StackTrace.current,
      );
      return;
    }

    debugPrint('ChatController: Starting message stream for user: $userId');
    _sub?.cancel();

    _sub = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at')
        .listen(
          (data) {
            debugPrint(
              'ChatController: Stream received ${data.length} messages',
            );

            final List<ChatMessage> streamed =
                data.map((item) {
                  return ChatMessage(
                    id: item['id'].toString(),
                    content: (item['content'] ?? '').toString(),
                    isUser: item['role'] == 'user', // ✅ FIX
                    createdAt: DateTime.parse(
                      item['created_at'] ?? DateTime.now().toIso8601String(),
                    ),
                  );
                }).toList();

            // Merge with current state to avoid overwriting optimistic updates
            final current = state.value ?? <ChatMessage>[];
            final List<ChatMessage> merged = [
              ...current,
              ...streamed.where((m) => !current.any((c) => c.id == m.id)),
            ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

            state = AsyncValue.data(merged);
          },
          onError: (error, stackTrace) {
            debugPrint('ChatController: Stream error: $error');
            state = AsyncValue.error(error, stackTrace);
          },
        );
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, AsyncValue<List<ChatMessage>>>((ref) {
      debugPrint('ChatControllerProvider: Creating new ChatController');
      return ChatController(ref);
    });
