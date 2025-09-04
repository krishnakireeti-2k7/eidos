import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController() : super(const AsyncValue.data(null));

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.eidos://login-callback/',
      );
      state = const AsyncValue.data(null);
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      await Supabase.instance.client.auth.signOut();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createUserInDb(User user) async {
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
        print('New user created in database.');
      } else {
        print('User already exists in database.');
      }
    } catch (e) {
      print('Error creating user in database: $e');
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController();
    });
