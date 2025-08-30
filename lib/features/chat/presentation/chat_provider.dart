import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/chat_repository.dart';
import '../data/chat_message.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository());

final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
      (ref) => ChatMessagesNotifier(ref),
    );

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref; // <-- changed from Reader
  ChatMessagesNotifier(this.ref) : super([]);

  Future<void> sendMessage(String text) async {
    // 1️⃣ Add user message optimistically
    state = [...state, ChatMessage(role: 'user', text: text)];

    // 2️⃣ Call Edge Function
    final reply = await ref.read(chatRepositoryProvider).sendMessage(text);

    // 3️⃣ Add assistant reply
    state = [...state, reply];
  }
}
