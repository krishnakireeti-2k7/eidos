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
  ChatController(this.ref) : super(const AsyncValue.data([]));

  final Ref ref;

  Future<void> fetchMessages() async {
    state = const AsyncValue.loading();
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      final messages =
          response
              .map(
                (data) => ChatMessage(
                  id: data['id'],
                  content: data['content'],
                  isUser: data['is_user'],
                  createdAt: DateTime.parse(data['created_at']),
                ),
              )
              .toList();

      state = AsyncValue.data(messages);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> sendMessage(String message) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await Supabase.instance.client.functions.invoke(
        'chat',
        body: {'message': message, 'userId': userId},
      );

      if (response.status != 200) {
        throw Exception('Failed to send message: ${response.data['error']}');
      }

      await fetchMessages();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, AsyncValue<List<ChatMessage>>>((ref) {
      return ChatController(ref)..fetchMessages();
    });
