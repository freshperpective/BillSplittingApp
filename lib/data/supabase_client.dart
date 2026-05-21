import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single source of truth for the configured Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Convenience: emits whenever the auth state changes.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// The current Supabase user, or null if signed out.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider); // re-evaluate on auth changes
  return ref.watch(supabaseClientProvider).auth.currentUser;
});
