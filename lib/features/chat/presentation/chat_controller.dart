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

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint('ChatController: Auth state changed: ${data.event}');
      if (data.event == AuthChangeEvent.initialSession ||
          data.event == AuthChangeEvent.signedIn) {
        _initOnce();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _sub?.cancel();
        _streamInitialized = false;
        _initialized = false;
        state = const AsyncValue.data([]);
      }
    });

    if (Supabase.instance.client.auth.currentUser != null) {
      _initOnce();
    }
  }

  final Ref ref;
  final String chatId;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription? _authSub;

  bool _initialized = false;
  bool _streamInitialized = false;
  bool _isDisposed = false;

  @override
  void dispose() {
    debugPrint('ChatController: Disposing chatId: $chatId');
    _isDisposed = true;
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _initOnce() async {
    if (_initialized || _isDisposed) return;
    _initialized = true;
    await fetchMessages(initial: true);
    _listenToMessages();
  }

  Future<void> fetchMessages({bool initial = false}) async {
    if (_isDisposed) return;
    debugPrint('ChatController: Fetching messages for chatId: $chatId...');

    if (initial && !_streamInitialized) {
      state = const AsyncValue.loading();
    }

    try {
      final response = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);

      final serverMessages =
          (response as List<dynamic>).map((data) {
            final createdAt =
                DateTime.parse(
                  (data['created_at'] ?? DateTime.now().toIso8601String())
                      .toString(),
                ).toUtc();
            return ChatMessage(
              id: data['id'].toString(),
              content: (data['content'] ?? '').toString(),
              isUser: (data['is_user'] ?? true) as bool,
              createdAt: createdAt,
            );
          }).toList();

      debugPrint(
        'ChatController: Fetched ${serverMessages.length} messages: ${serverMessages.map((m) => '[id=${m.id}, content=${m.content}, isUser=${m.isUser}, createdAt=${m.createdAt}]').toList()}',
      );

      if (!_streamInitialized) {
        state = AsyncValue.data(serverMessages);
      }
    } catch (e, st) {
      debugPrint('ChatController: Fetch messages error: $e');
      if (initial && !_streamInitialized) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> sendMessage(String message) async {
    debugPrint('ChatController: Sending message: $message');

    final current = state.value ?? <ChatMessage>[];
    final localUserId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    final localUser = ChatMessage(
      id: localUserId,
      content: message,
      isUser: true,
      createdAt: DateTime.now().toUtc(),
    );

    // Optimistic UI for user message
    final updated = [...current, localUser];
    state = AsyncValue.data(updated);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Call API service (backend stores user and assistant messages)
      final apiService = ref.read(apiServiceProvider);
      final reply = await apiService.sendMessage(
        message,
        userId: userId,
        chatId: chatId,
        requireAuth: true,
      );

      debugPrint('ChatController: ApiService reply: $reply');

      // Optimistic UI for assistant message
      final localAssistantId =
          'local-assistant-${DateTime.now().millisecondsSinceEpoch}';
      final localAssistant = ChatMessage(
        id: localAssistantId,
        content: reply,
        isUser: false,
        createdAt: DateTime.now().toUtc(),
      );

      final after = [...(state.value ?? <ChatMessage>[]), localAssistant];
      state = AsyncValue.data(after);

      // Invalidate provider to force stream update
      ref.invalidateSelf();
    } catch (e, st) {
      debugPrint('ChatController: Send message error: $e');
      final reverted =
          (state.value ?? <ChatMessage>[])
              .where((m) => m.id != localUserId)
              .toList();
      state = AsyncValue.data(reverted);
    }
  }

  void _listenToMessages() {
    debugPrint('ChatController: Starting message stream for chatId: $chatId');

    _sub?.cancel();

    try {
      final stream = Supabase.instance.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);

      _sub = stream.listen(
        (data) {
          if (_isDisposed) return;

          final serverRows =
              data.map((item) {
                final createdAt =
                    DateTime.parse(item['created_at'].toString()).toUtc();
                return ChatMessage(
                  id: item['id'].toString(),
                  content: (item['content'] ?? '').toString(),
                  isUser: (item['is_user'] ?? true) as bool,
                  createdAt: createdAt,
                );
              }).toList();

          debugPrint(
            'ChatController: Stream emitted ${serverRows.length} rows: ${serverRows.map((m) => '[id=${m.id}, content=${m.content}, isUser=${m.isUser}, createdAt=${m.createdAt}]').toList()}',
          );

          // Clear local placeholders and use server data
          final merged = _mergeServerWithLocals(serverRows, state.value ?? []);
          state = AsyncValue.data(merged);
          _streamInitialized = true;
        },
        onError: (error, stackTrace) {
          debugPrint('ChatController: Stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('ChatController: _listenToMessages exception: $e');
    }
  }

  List<ChatMessage> _mergeServerWithLocals(
    List<ChatMessage> server,
    List<ChatMessage> current,
  ) {
    final Map<String, ChatMessage> out = {};

    // Prioritize server messages
    for (final m in server) {
      out[m.id] = m;
    }

    // Keep local placeholders only if no server message matches by content and isUser
    for (final m in current) {
      if (m.id.startsWith('local-')) {
        final existsOnServer = server.any(
          (s) => s.content.trim() == m.content.trim() && s.isUser == m.isUser,
        );
        if (!existsOnServer) {
          out[m.id] = m;
        } else {
          debugPrint(
            'ChatController: Discarding local placeholder id=${m.id}, content=${m.content} as server match found',
          );
        }
      }
    }

    final merged =
        out.values.toList()..sort((a, b) {
          final cmp = a.createdAt.compareTo(b.createdAt);
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });

    debugPrint(
      'ChatController: Merged ${merged.length} messages: ${merged.map((m) => '[id=${m.id}, content=${m.content}, isUser=${m.isUser}, createdAt=${m.createdAt}]').toList()}',
    );

    return merged;
  }

  bool _isSameMessageByContentAndTime(
    ChatMessage a,
    ChatMessage b, {
    int secondsTolerance = 5,
  }) {
    final contentA = a.content.trim();
    final contentB = b.content.trim();
    if (contentA != contentB || a.isUser != b.isUser) return false;
    final diff = a.createdAt.difference(b.createdAt).inSeconds.abs();
    return diff <= secondsTolerance;
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
