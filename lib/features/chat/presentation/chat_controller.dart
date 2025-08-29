// lib/features/chat/presentation/chat_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eidos/services/api_services.dart'; // Make sure the path is correct

// Define a simple Message class to hold message data
class Message {
  final String text;
  final String role; // 'user' or 'assistant'
  Message({required this.text, required this.role});
}

// State class for the chat controller
class ChatState {
  final List<Message> messages;
  final bool isLoading;

  ChatState({required this.messages, this.isLoading = false});

  // Helper method to create a new state with updated messages
  ChatState copyWith({List<Message>? messages, bool? isLoading}) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// The StateNotifier
class ChatController extends StateNotifier<ChatState> {
  ChatController(this.apiService) : super(ChatState(messages: []));

  final ApiService apiService;

  Future<void> sendMessage(String text) async {
    // Optimistically add the user's message to the list
    state = state.copyWith(
      messages: [...state.messages, Message(text: text, role: 'user')],
      isLoading: true,
    );

    try {
      final reply = await apiService.sendMessage(text);
      // Add the assistant's reply
      state = state.copyWith(
        messages: [...state.messages, Message(text: reply, role: 'assistant')],
        isLoading: false,
      );
    } catch (e) {
      // Handle the error and show it to the user
      state = state.copyWith(
        messages: [
          ...state.messages,
          Message(text: 'Error: $e', role: 'assistant'),
        ],
        isLoading: false,
      );
    }
  }
}

// The Riverpod provider to make the controller accessible
final apiServiceProvider = Provider((ref) => ApiService());

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) {
    final apiService = ref.watch(apiServiceProvider);
    return ChatController(apiService);
  },
);
