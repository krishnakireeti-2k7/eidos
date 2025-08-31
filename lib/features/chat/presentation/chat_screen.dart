import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EIDOS Chat')),
      body: const Center(child: Text('Auth Successful! Ready for Chat')),
    );
  }
}
