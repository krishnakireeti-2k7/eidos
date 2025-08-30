import 'dart:convert';
import 'package:http/http.dart' as http;
import 'chat_message.dart';

class ChatRepository {
  final String edgeFunctionUrl =
      'https://ezmmdycldxnpmdbdmddq.supabase.co/functions/v1/chat-send';

  Future<ChatMessage> sendMessage(String text) async {
    final response = await http.post(
      Uri.parse(edgeFunctionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ChatMessage(role: 'assistant', text: data['reply']);
    } else {
      throw Exception('Failed to send message: ${response.body}');
    }
  }
}
