// lib/features/chat/presentation/chat_screen.dart
import 'package:eidos/features/auth/presentation/auth_controller.dart';
import 'package:eidos/features/chat/presentation/chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Stream provider for user's chat list
final chatListProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();
    return Supabase.instance.client
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  },
);

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  ConsumerState createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late String _activeChatId;
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _activeChatId = widget.chatId;
    _textController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _createNewChat() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final response =
        await Supabase.instance.client
            .from('chats')
            .insert({'user_id': userId, 'title': 'New Chat'})
            .select()
            .single();

    setState(() {
      _activeChatId = response['id'];
    });

    Navigator.pop(context); // close drawer
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    var chatId = _activeChatId;

    // If chat does not exist yet, create it
    if (chatId.isEmpty) {
      final newChat =
          await Supabase.instance.client
              .from('chats')
              .insert({'user_id': userId, 'title': text})
              .select()
              .single();

      chatId = newChat['id'] as String;
      setState(() {
        _activeChatId = chatId;
      });
    }

    _textController.clear();

    await ref.read(chatControllerProvider(chatId).notifier).sendMessage(text);

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatControllerProvider(_activeChatId));
    ref.listen(chatControllerProvider(_activeChatId), (prev, next) {
      if (next is AsyncData) _scrollToBottom();
    });

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text("EIDOS"),
        backgroundColor: const Color(0xFF1A1A2E),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
      ),
      drawer: Drawer(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF16213E), Color(0xFF1A1A2E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    "Your Chats",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(color: Colors.white54, height: 1),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final chatsAsync = ref.watch(chatListProvider);
                      return chatsAsync.when(
                        data: (chats) {
                          if (chats.isEmpty) {
                            return const Center(
                              child: Text(
                                "No chats yet",
                                style: TextStyle(color: Colors.white70),
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: chats.length,
                            itemBuilder: (context, index) {
                              final chat = chats[index];
                              final isActive = chat['id'] == _activeChatId;
                              return ListTile(
                                leading: Icon(
                                  Icons.chat_bubble_outline,
                                  color: isActive ? Colors.white : Colors.blue,
                                ),
                                title: Text(
                                  chat['title'] ?? 'Untitled',
                                  style: TextStyle(
                                    color:
                                        isActive
                                            ? Colors.white
                                            : Colors.white70,
                                    fontWeight:
                                        isActive
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                                tileColor:
                                    isActive
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.transparent,
                                onTap: () {
                                  setState(() {
                                    _activeChatId = chat['id'];
                                  });
                                  Navigator.pop(context); // close drawer
                                },
                              );
                            },
                          );
                        },
                        loading:
                            () => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                        error:
                            (e, st) => Center(
                              child: Text(
                                'Error: $e',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                      );
                    },
                  ),
                ),
                const Divider(color: Colors.white54, height: 1),
                ListTile(
                  leading: const Icon(Icons.add, color: Colors.green),
                  title: const Text(
                    "New Chat",
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: _createNewChat,
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    "Logout",
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).signOut();
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/auth');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: messagesAsync.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _ChatMessageBubble(message: message);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (e, st) => Center(
                      child: Text(
                        'Error: $e',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        hintStyle: const TextStyle(color: Colors.grey),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF4285F4)),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? const Color(0xFF4285F4) : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
