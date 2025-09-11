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

    // Watch auth changes but initialize only once (prevents duplicate fetches)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint('ChatController: Auth state changed: ${data.event}');
      if (data.event == AuthChangeEvent.initialSession ||
          data.event == AuthChangeEvent.signedIn) {
        _initOnce();
      } else if (data.event == AuthChangeEvent.signedOut) {
        // cleanup on sign out
        _sub?.cancel();
        _streamInitialized = false;
        _initialized = false;
        state = const AsyncValue.data([]);
      }
    });

    // If already signed in, init immediately
    if (Supabase.instance.client.auth.currentUser != null) {
      _initOnce();
    }
  }

  final Ref ref;
  final String chatId;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription? _authSub;

  bool _initialized = false; // ensures we only init once
  bool _streamInitialized = false; // marks that stream emitted at least once
  bool _isDisposed = false;

  @override
  void dispose() {
    debugPrint('ChatController: Disposing chatId: $chatId');
    _isDisposed = true;
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // One-time initialization sequence
  Future<void> _initOnce() async {
    if (_initialized || _isDisposed) return;
    _initialized = true;
    await fetchMessages(initial: true);
    _listenToMessages();
  }

  /// Fetch messages from Supabase. If [initial] is true, show loading and set state.
  /// If stream already initialized, merge server rows with local placeholders instead of overwriting.
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

      serverMessages.sort((a, b) {
        final cmp = a.createdAt.compareTo(b.createdAt);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });

      debugPrint('ChatController: Fetched ${serverMessages.length} messages');

      // ✅ Only update state if stream hasn't already taken over
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

  /// Send message: optimistic local placeholder -> insert user message -> call API -> insert assistant message
  Future<void> sendMessage(String message) async {
    debugPrint('ChatController: Sending message: $message');

    final current = state.value ?? <ChatMessage>[];
    final local = ChatMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      content: message,
      isUser: true,
      createdAt: DateTime.now().toUtc(),
    );

    // optimistic UI
    state = AsyncValue.data(
      [...current, local]..sort((a, b) {
        final cmp = a.createdAt.compareTo(b.createdAt);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      }),
    );

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Insert user message (get DB row)
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
        createdAt:
            DateTime.parse(insertResponse['created_at'].toString()).toUtc(),
      );

      // replace local placeholder with DB row
      final replaced =
          (state.value ?? <ChatMessage>[])
              .map((m) => m.id == local.id ? insertedMessage : m)
              .toList();
      replaced.sort((a, b) {
        final cmp = a.createdAt.compareTo(b.createdAt);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });
      state = AsyncValue.data(replaced);

      // Call API service for assistant reply
      final apiService = ref.read(apiServiceProvider);
      final reply = await apiService.sendMessage(
        message,
        userId: userId,
        chatId: chatId,
        requireAuth: true,
      );

      debugPrint('ChatController: ApiService reply: $reply');

      // Try to insert assistant message into DB (use same user_id so RLS passes)
      try {
        final assistantInsert =
            await Supabase.instance.client
                .from('messages')
                .insert({
                  'chat_id': chatId,
                  'user_id': userId,
                  'content': reply,
                  'is_user': false,
                })
                .select()
                .single();

        final assistant = ChatMessage(
          id: assistantInsert['id'].toString(),
          content: assistantInsert['content'],
          isUser: false,
          createdAt:
              DateTime.parse(assistantInsert['created_at'].toString()).toUtc(),
        );

        // Append assistant if stream hasn't already provided it.
        final afterAssistant = [...(state.value ?? <ChatMessage>[])];
        if (!afterAssistant.any((m) => m.id == assistant.id)) {
          afterAssistant.add(assistant);
        }
        afterAssistant.sort((a, b) {
          final cmp = a.createdAt.compareTo(b.createdAt);
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
        state = AsyncValue.data(afterAssistant);
      } catch (e) {
        // If DB insert fails (RLS or other), fall back to showing a local assistant placeholder
        debugPrint(
          'ChatController: Assistant insert failed, falling back to local placeholder: $e',
        );

        final assistantLocal = ChatMessage(
          id: 'local-assistant-${DateTime.now().millisecondsSinceEpoch}',
          content: reply,
          isUser: false,
          createdAt: DateTime.now().toUtc(),
        );

        final afterAssistant = [...(state.value ?? <ChatMessage>[])];
        // only add if there's no very similar server message already
        final hasSimilar = afterAssistant.any(
          (m) =>
              !m.id.startsWith('local-') &&
              _isSameMessageByContentAndTime(
                m,
                assistantLocal,
                secondsTolerance: 2,
              ),
        );
        if (!hasSimilar) {
          afterAssistant.add(assistantLocal);
          afterAssistant.sort((a, b) {
            final cmp = a.createdAt.compareTo(b.createdAt);
            return cmp != 0 ? cmp : a.id.compareTo(b.id);
          });
          state = AsyncValue.data(afterAssistant);
        }
      }
    } catch (e, st) {
      debugPrint('ChatController: Send message error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  /// Realtime listener: server rows are authoritative; we merge server rows with any local placeholders.
  void _listenToMessages() {
    debugPrint('ChatController: Starting message stream for chatId: $chatId');

    _sub?.cancel();

    try {
      final stream = Supabase.instance.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('chat_id', chatId)
          .order('created_at');

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

          serverRows.sort((a, b) {
            final cmp = a.createdAt.compareTo(b.createdAt);
            return cmp != 0 ? cmp : a.id.compareTo(b.id);
          });

          if (!_streamInitialized) {
            // 🔑 First emission: replace fetchMessages result completely
            state = AsyncValue.data(serverRows);
            _streamInitialized = true;
            debugPrint(
              'ChatController: Stream first emit -> ${serverRows.length} messages (replaced)',
            );
          } else {
            // Later emissions: only merge with any local placeholders
            final merged = _mergeServerWithLocals(
              serverRows,
              state.value ?? [],
            );
            state = AsyncValue.data(merged);
            debugPrint(
              'ChatController: Stream emitted ${serverRows.length} rows, merged -> ${merged.length}',
            );
          }
        },
        onError: (error, stackTrace) {
          debugPrint('ChatController: Stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('ChatController: _listenToMessages exception: $e');
    }
  }

  /// Merge server rows (authoritative) with local placeholders.
  /// - Keeps server rows (authoritative).
  /// - Keeps local placeholders only if server doesn't already have the same message (by content + time proximity).
  List<ChatMessage> _mergeServerWithLocals(
    List<ChatMessage> server,
    List<ChatMessage> current,
  ) {
    final Map<String, ChatMessage> out = {};

    // add server rows first (authoritative)
    for (final m in server) {
      out[m.id] = m;
    }

    // Keep local placeholders that server hasn't returned yet (id starts with 'local-'),
    // but skip placeholders that appear to already exist on the server (matching content + time)
    for (final m in current) {
      if (m.id.startsWith('local-')) {
        final existsOnServer = server.any(
          (s) => _isSameMessageByContentAndTime(s, m, secondsTolerance: 2),
        );
        if (!existsOnServer) {
          out[m.id] = m;
        } // else skip local placeholder because server already has equivalent
      } else {
        // non-local rows already from server or previous inserts — they will be in 'out' by id
        if (!out.containsKey(m.id)) {
          out[m.id] = m;
        }
      }
    }

    final merged =
        out.values.toList()..sort((a, b) {
          final cmp = a.createdAt.compareTo(b.createdAt);
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });

    return merged;
  }

  bool _isSameMessageByContentAndTime(
    ChatMessage a,
    ChatMessage b, {
    int secondsTolerance = 2,
  }) {
    final contentA = a.content.trim();
    final contentB = b.content.trim();
    if (contentA != contentB) return false;
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
