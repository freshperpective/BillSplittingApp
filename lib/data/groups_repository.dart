import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';
import 'supabase_client.dart';

class GroupsRepository {
  GroupsRepository(this._client);

  final SupabaseClient _client;

  /// Returns groups the current user is a member of, most-recent first.
  Future<List<Group>> listMyGroups() async {
    final rows = await _client
        .from('groups')
        .select('id,name,emoji,default_currency,created_by,archived_at,created_at,'
            'group_members!inner(profile_id)')
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Group.fromJson)
        .toList();
  }

  Future<Group> createGroup({
    required String name,
    required String emoji,
    required String defaultCurrency,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    final row = await _client
        .from('groups')
        .insert({
          'name': name,
          'emoji': emoji,
          'default_currency': defaultCurrency,
          'created_by': user.id,
        })
        .select()
        .single();

    // The owner is auto-added by the `on_group_created` trigger server-side.
    // Do not mirror the insert from the client — a client-side upsert here
    // would become an UPDATE on the row the trigger already inserted, and
    // `group_members` has no UPDATE RLS policy, which surfaces as 42501.

    return Group.fromJson(row);
  }

  Future<List<Profile>> listMembers(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select('profiles(id,display_name,avatar_url,default_currency)')
        .eq('group_id', groupId);
    return (rows as List)
        .map((r) => Profile.fromJson(
              (r['profiles'] as Map).cast<String, dynamic>(),
            ))
        .toList();
  }

  /// Look up an existing user by their account email. Returns null when no
  /// account exists for that email. Uses the `find_profile_by_email` RPC
  /// (SECURITY DEFINER) because RLS prevents direct reads of profiles you
  /// don't share a group with.
  Future<Profile?> findProfileByEmail(String email) async {
    final res = await _client
        .rpc('find_profile_by_email', params: {'p_email': email});
    if (res is List && res.isNotEmpty) {
      final row = (res.first as Map).cast<String, dynamic>();
      return Profile(
        id: row['id'] as String,
        displayName: row['display_name'] as String? ?? 'Unknown',
      );
    }
    return null;
  }

  /// Add a profile to a group. RLS allows this only when the caller is an
  /// owner of the group OR they're adding themselves.
  Future<void> addMember({
    required String groupId,
    required String profileId,
    String role = 'member',
  }) async {
    await _client.from('group_members').insert({
      'group_id': groupId,
      'profile_id': profileId,
      'role': role,
    });
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(supabaseClientProvider));
});

/// All groups the current user is in, most-recent first.
final myGroupsProvider = FutureProvider<List<Group>>((ref) async {
  return ref.watch(groupsRepositoryProvider).listMyGroups();
});

/// Members (profiles) of one group. UI invalidates this after add-member.
final groupMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, groupId) async {
  return ref.watch(groupsRepositoryProvider).listMembers(groupId);
});
