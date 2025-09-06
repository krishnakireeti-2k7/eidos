// lib/features/auth/presentation/auth_screen.dart
import 'package:eidos/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    // This is the updated code block to print the token in chunks
    ref.listen(authControllerProvider, (_, state) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final fullToken = session.accessToken;
        const chunkSize = 200;
        print('--- START OF FULL JWT TOKEN ---');
        for (int i = 0; i < fullToken.length; i += chunkSize) {
          int end =
              (i + chunkSize < fullToken.length)
                  ? i + chunkSize
                  : fullToken.length;
          print(fullToken.substring(i, end));
        }
        print('--- END OF FULL JWT TOKEN ---');
      }
    });

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
              authState.isLoading
                  ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                  : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: ElevatedButton.icon(
                      onPressed:
                          () =>
                              ref
                                  .read(authControllerProvider.notifier)
                                  .signInWithGoogle(),
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
                        backgroundColor: const Color(0xFF4285F4),
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
              if (authState.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    authState.error.toString(),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
