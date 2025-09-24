import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/chat/presentation/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://otckcbxbwqvojmdeskqf.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im90Y2tjYnhid3F2b2ptZGVza3FmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY2Mjc4NzcsImV4cCI6MjA3MjIwMzg3N30.6LUgVtcaf7cD8mwPNb67qdmAXU6aZFDyduNsImi6HUg',
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (data.event == AuthChangeEvent.signedIn && session != null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          ref.read(authControllerProvider.notifier).createUserInDb(user);

          // Debug info for testing
          final jwt = session.accessToken;
          final userId = user.id;
          print('--- COPIED FOR EDGE FUNCTION TESTING ---');
          print('User ID: $userId');
          print('JWT Token: $jwt');
          print('-----------------------------------------');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EIDOS',
      theme: ThemeData.dark(),
      home: StreamBuilder(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final session = snapshot.data?.session;

          if (session != null) {
            return const ChatScreen();
          } else {
            return const AuthScreen();
          }
        },
      ),

    );
  }
}
