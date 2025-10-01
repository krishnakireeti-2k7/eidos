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

    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context); // Close drawer
    }
  }

  // Renaming functionality is now handled within the _ChatHistoryItem

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
      // Logic to create a new chat on first message
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

    // Call the chat controller to handle sending the message
    // Note: Assuming 'chatControllerProvider' and 'sendMessage' logic is correct.
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
        width: 300,
        child: Container(
          // UPDATED: Use the primary dark color for consistency
          color: const Color(0xFF1A1A2E),
          child: SafeArea(
            child: Column(
              children: [
                // New Chat Button
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: OutlinedButton(
                    onPressed: _createNewChat,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(
                        color: Colors.white10,
                      ), // Very subtle border
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      backgroundColor: const Color(
                        0xFF1E293B,
                      ), // Dark blue-gray for the button
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: const [
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'New Chat',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final chatsAsync = ref.watch(chatListProvider);
                      return chatsAsync.when(
                        data: (chats) {
                          if (chats.isEmpty) {
                            return const Center(
                              child: Text(
                                'No chats yet',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: chats.length,
                            itemBuilder: (context, index) {
                              final chat = chats[index];
                              return _ChatHistoryItem(
                                chat: chat,
                                isActive: chat['id'] == activeChatId,
                                // Passing ref to allow _ChatHistoryItem to use providers
                                ref: ref,
                              );
                            },
                          );
                        },
                        loading:
                            () => const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF4285F4),
                              ),
                            ),
                        error:
                            (e, st) => Center(
                              child: Text(
                                'Error: $e',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                      );
                    },
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                // Footer: Logout Button
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: InkWell(
                    onTap: () async {
                      await ref.read(authControllerProvider.notifier).signOut();
                      if (mounted) {
                        Navigator.pushReplacementNamed(context, '/auth');
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    // Use the slightly lighter drawer color for the hover state
                    hoverColor: const Color(0xFF1E293B),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.transparent, // Maintain transparency
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFF44336), // Red color for logout
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 60,
                              color: Colors.white38,
                            ),
                            SizedBox(height: 16),
                            const Text(
                              'Start a new chat with EIDOS',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 18,
                              ),
                            ),
                          ],
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
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                    ),
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
                        // Use a slightly darker gray for the input field background
                        fillColor: const Color(0xFF121212),
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

// ----------------------------------------------------------------------
// UPDATED WIDGETS
// ----------------------------------------------------------------------

class _ChatHistoryItem extends ConsumerStatefulWidget {
  final Map<String, dynamic> chat;
  final bool isActive;
  final WidgetRef ref; // Pass ref explicitly to use it in rename

  const _ChatHistoryItem({
    required this.chat,
    required this.isActive,
    required this.ref,
  });

  @override
  ConsumerState<_ChatHistoryItem> createState() => _ChatHistoryItemState();
}

class _ChatHistoryItemState extends ConsumerState<_ChatHistoryItem> {
  bool _isHovering = false;

  Future<void> _renameChat() async {
    final currentTitle = widget.chat['title'] ?? 'Untitled';
    final chatId = widget.chat['id'];

    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            // Match the overall dark theme for the dialog
            backgroundColor: const Color(0xFF1E293B),
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
                // Match the new chat button background
                fillColor: const Color(0xFF16213E),
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
      widget.ref.invalidate(chatListProvider); // Refresh drawer
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the background color based on active state and hover state
    Color tileColor = Colors.transparent;
    if (widget.isActive) {
      tileColor = const Color(0xFF1E293B); // Active chat color
    } else if (_isHovering) {
      tileColor = const Color(0xFF16213E); // Subtle hover color
    }

    // Determine the text color
    Color textColor = widget.isActive ? Colors.white : Colors.white70;

    return Dismissible(
      key: ValueKey(widget.chat['id']),
      direction: DismissDirection.endToStart,
      // Temporarily disable the action as per user request
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // You can add your delete confirmation logic here later
          return false;
        }
        return false;
      },
      background: Container(
        color: const Color(
          0xFFF44336,
        ).withOpacity(0.5), // Delete color placeholder
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_forever, color: Colors.white70),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(
              Icons.chat_bubble_outline_rounded,
              color: textColor,
              size: 20,
            ),
            title: Text(
              widget.chat['title'] ?? 'Untitled Chat',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Edit button on Long Press only
            trailing:
                widget.isActive || _isHovering
                    ? PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'rename') {
                          await _renameChat();
                        }
                        // Add delete logic here later if desired
                      },
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.edit_outlined,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Rename',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            // Delete option hidden for now
                          ],
                      icon: Icon(Icons.more_horiz, color: textColor, size: 20),
                      // Ensure the menu itself matches the dark palette
                      color: const Color(0xFF16213E),
                      surfaceTintColor:
                          Colors
                              .transparent, // To remove the default elevated color tint
                    )
                    : null,
            onTap: () {
              widget.ref.read(activeChatIdProvider.notifier).state =
                  widget.chat['id'];
              Navigator.pop(context); // Close drawer
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// UNCHANGED WIDGETS
// ----------------------------------------------------------------------

class _ChatMessageBubble extends StatelessWidget {
  final dynamic message;
  const _ChatMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    // Determine if the message is from the user or the assistant (EIDOS)
    // Assuming 'role' field exists in your message data
    final bool isUser =
        message is Map ? message['role'] == 'user' : message.isUser;
    final String content =
        message is Map ? message['content'] : message.content;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF4285F4) : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(content, style: const TextStyle(color: Colors.white)),
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
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.2, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Text(
                'EIDOS is thinking...',
                style: TextStyle(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  shadows: [
                    Shadow(
                      color: const Color(
                        0xFF4285F4,
                      ).withOpacity(_glowAnimation.value),
                      blurRadius: 4 + (6 * _glowAnimation.value),
                      offset: const Offset(0, 0),
                    ),
                    Shadow(
                      color: const Color(
                        0xFF4285F4,
                      ).withOpacity(_glowAnimation.value * 0.5),
                      blurRadius: 8 + (4 * _glowAnimation.value),
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
