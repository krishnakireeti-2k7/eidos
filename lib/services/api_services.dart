// lib/services/api_service.dart
// You'll need to add a http dependency to your pubspec.yaml file
// In your terminal run: flutter pub add http
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String _baseUrl =
      'YOUR_BACKEND_URL_HERE'; // Replace with your actual backend URL

  Future<String> sendMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['reply']; // The backend will return a JSON with a 'reply' key
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error sending message: $e');
    }
  }
}
