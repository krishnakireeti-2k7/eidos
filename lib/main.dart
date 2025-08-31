// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/chat/presentation/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://otckcbxbwqvojmdeskqf.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im90Y2tjYnhid3F2b2ptZGVza3FmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY2Mjc4NzcsImV4cCI6MjA3MjIwMzg3N30.6LUgVtcaf7cD8mwPNb67qdmAXU6aZFDyduNsImi6HUg',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EIDOS',
      theme: ThemeData.dark(),
      // Use a StreamBuilder to listen for real-time auth changes
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final session = snapshot.data?.session;
          if (session != null) {
            // User is signed in
            return const ChatScreen();
          } else {
            // User is not signed in
            return const AuthScreen();
          }
        },
      ),
    );
  }
}
