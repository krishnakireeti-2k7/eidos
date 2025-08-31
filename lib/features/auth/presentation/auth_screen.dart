// lib/features/auth/presentation/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      print('Attempting Google sign-in');
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.eidos://login-callback/',
      );
      print('Google sign-in initiated, awaiting redirect');
    } catch (e) {
      print('Google sign-in error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // This listener now only handles database insertion.
    // The main.dart StreamBuilder handles the navigation.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (data.event == AuthChangeEvent.signedIn && session != null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          try {
            final existing =
                await Supabase.instance.client
                    .from('users')
                    .select()
                    .eq('id', user.id)
                    .maybeSingle();
            if (existing == null) {
              await Supabase.instance.client.from('users').insert({
                'id': user.id,
                'email': user.email!,
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          } catch (e) {
            print('Error inserting user: $e');
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'EIDOS',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(
                      blurRadius: 10,
                      color: Colors.black26,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                  : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: ElevatedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(
                        Icons.g_mobiledata,
                        size: 24,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Sign In with Google',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4), // Google Blue
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                        shadowColor: Colors.black45,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
