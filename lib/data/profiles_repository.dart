import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';
import 'supabase_client.dart';

/// Read + self-update on the current user's profile. RLS already lets a
/// user select their own row (and any peer's, via shared groups) and
/// update only their own — those policies live in migration 0001.
class ProfilesRepository {
  ProfilesRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> getMine() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('id,display_name,avatar_url,default_currency')
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(row);
  }

  /// Partial update — pass only the fields you want to change. Avatar URL
  /// will land here too once Supabase Storage is wired up for uploads.
  Future<Profile> updateMine({
    String? displayName,
    String? defaultCurrency,
    String? avatarUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final patch = <String, dynamic>{};
    if (displayName != null) patch['display_name'] = displayName;
    if (defaultCurrency != null) patch['default_currency'] = defaultCurrency;
    if (avatarUrl != null) patch['avatar_url'] = avatarUrl;
    if (patch.isEmpty) {
      // Nothing to do — return the current row so the caller still gets
      // a usable Profile back.
      final p = await getMine();
      if (p == null) throw StateError('Profile missing');
      return p;
    }

    final row = await _client
        .from('profiles')
        .update(patch)
        .eq('id', user.id)
        .select()
        .single();
    return Profile.fromJson(row);
  }
}

final profilesRepositoryProvider = Provider<ProfilesRepository>((ref) {
  return ProfilesRepository(ref.watch(supabaseClientProvider));
});

/// Current user's profile. Returns null when signed out. Invalidated after
/// any successful updateMine call so the profile tab repaints.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  // Re-trigger when auth state flips (login/logout) so we don't hold a
  // stale profile across users on the same device.
  ref.watch(authStateProvider);
  return ref.watch(profilesRepositoryProvider).getMine();
});
