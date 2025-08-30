import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/presentation/auth_screen.dart'; // Or your entry screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL', // From Supabase dashboard
    anonKey: 'YOUR_ANON_KEY', // Public anon key (safe for client)
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EIDOS Memory Chat',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AuthScreen(), // Start with auth
    );
  }
}
