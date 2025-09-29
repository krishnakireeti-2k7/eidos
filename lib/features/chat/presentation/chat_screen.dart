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

// State provider for active chat ID
final activeChatIdProvider = StateProvider<String?>((ref) => null);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitializing = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _scrollController = ScrollController();
    _initializeChatId();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChatId() async {
    // Start with home screen (no active chat)
    ref.read(activeChatIdProvider.notifier).state = null;
    setState(() {
      _isInitializing = false;
    });
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

  Future<void> _ensureUserExists() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client.from('users').upsert({
      'id': user.id,
      'email': user.email,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _createNewChat() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    await _ensureUserExists();

    final response =
        await Supabase.instance.client
            .from('chats')
            .insert({'user_id': userId, 'title': 'New Chat'})
            .select()
            .single();

    ref.read(activeChatIdProvider.notifier).state = response['id'];
    ref.invalidate(chatListProvider); // Update drawer

    Navigator.pop(context); // Close drawer
  }

  Future<void> _renameChat(String chatId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'Rename Chat',
              style: TextStyle(color: Colors.white),
            ),
            content: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter chat name',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLength: 50,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: () {
                  final title = controller.text.trim();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat name cannot be empty'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, title);
                },
                child: const Text(
                  'Save',
                  style: TextStyle(color: Color(0xFF4285F4)),
                ),
              ),
            ],
          ),
    );

    if (newTitle == null || newTitle.trim() == currentTitle) return;

    try {
      await Supabase.instance.client
          .from('chats')
          .update({'title': newTitle.trim()})
          .eq('id', chatId);
      ref.invalidate(chatListProvider); // Refresh drawer
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to rename chat: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isSending = false;
      });
      return;
    }

    await _ensureUserExists();

    String chatId;
    final currentChatId = ref.read(activeChatIdProvider);

    if (currentChatId == null) {
      final newChat =
          await Supabase.instance.client
              .from('chats')
              .insert({'user_id': userId, 'title': text})
              .select()
              .single();

      chatId = newChat['id'] as String;
      ref.read(activeChatIdProvider.notifier).state = chatId;
      ref.invalidate(chatListProvider); // Update drawer
    } else {
      chatId = currentChatId;
    }

    _textController.clear();

    await ref.read(chatControllerProvider(chatId).notifier).sendMessage(text);

    setState(() {
      _isSending = false;
    });

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final activeChatId = ref.watch(activeChatIdProvider);

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
                              final isActive = chat['id'] == activeChatId;
                              return GestureDetector(
                                onLongPressStart: (details) async {
                                  final selected = await showMenu<String>(
                                    context: context,
                                    position: RelativeRect.fromLTRB(
                                      details.globalPosition.dx,
                                      details.globalPosition.dy,
                                      details.globalPosition.dx,
                                      details.globalPosition.dy,
                                    ),
                                    color: Colors.grey[900],
                                    items: [
                                      PopupMenuItem<String>(
                                        value: 'rename',
                                        child: Row(
                                          children: const [
                                            Icon(
                                              Icons.edit,
                                              color: Colors.white70,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Rename',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );

                                  if (selected == 'rename') {
                                    await _renameChat(
                                      chat['id'],
                                      chat['title'] ?? 'Untitled',
                                    );
                                  }
                                },
                                child: ListTile(
                                  leading: Icon(
                                    Icons.chat_bubble_outline,
                                    color:
                                        isActive ? Colors.white : Colors.blue,
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
                                    ref
                                        .read(activeChatIdProvider.notifier)
                                        .state = chat['id'];
                                    Navigator.pop(context);
                                  },
                                ),
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
              child:
                  activeChatId == null
                      ? const Center(
                        child: Text(
                          'Start a new chat',
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                      : ref
                          .watch(chatControllerProvider(activeChatId))
                          .when(
                            data: (messages) {
                              return ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount:
                                    messages.length + (_isSending ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (_isSending && index == messages.length) {
                                    return const TypingIndicator();
                                  }
                                  final message = messages[index];
                                  return _ChatMessageBubble(message: message);
                                },
                              );
                            },
                            loading:
                                () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
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
                      enabled: !_isSending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon:
                        _isSending
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4285F4),
                              ),
                            )
                            : const Icon(Icons.send, color: Color(0xFF4285F4)),
                    onPressed: _isSending ? null : _send,
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

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);

    _opacity = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _scale = Tween<double>(
      begin: 0.98,
      end: 1.02,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: Text(
                "EIDOS is thinking...",
                style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.white.withOpacity(_opacity.value * 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
