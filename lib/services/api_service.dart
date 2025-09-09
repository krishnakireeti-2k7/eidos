// lib/services/api_service.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Deployed functions domain (use the functions.supabase.co domain you deployed to)
  final String _functionsBase =
      'https://otckcbxbwqvojmdeskqf.functions.supabase.co';

  /// Sends a message to the /chat Edge Function and returns Gemini's reply.
  ///
  /// - `text`: user message to send
  /// - `userId`: optional; if omitted the current Supabase user's id will be used (if available)
  /// - `requireAuth`: if true and no JWT is available, this will throw. Default false to allow public functions.
  Future<String> sendMessage(
    String text, {
    String? userId,
    bool requireAuth = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final jwt = session?.accessToken;
    final currentUserId = userId ?? session?.user?.id;

    if (requireAuth && jwt == null) {
      throw Exception('User not authenticated.');
    }

    final uri = Uri.parse('$_functionsBase/chat');
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (jwt != null) {
      headers['Authorization'] = 'Bearer $jwt';
    }

    final payload = <String, dynamic>{
      'message': text,
      if (currentUserId != null) 'userId': currentUserId,
    };

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(timeout);

      if (resp.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(resp.body);
        // Your Edge Function returns { "response": "..." }
        final String? reply = (data['response'] ?? data['message'])?.toString();
        return reply ?? resp.body;
      } else {
        throw Exception(
          'Failed to send message: ${resp.statusCode} - ${resp.body}',
        );
      }
    } catch (e) {
      throw Exception('Error sending message: $e');
    }
  }
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
