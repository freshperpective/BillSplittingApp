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

    // The owner is auto-added via a trigger server-side. Mirror that here in
    // case the trigger isn't deployed yet.
    await _client.from('group_members').upsert({
      'group_id': row['id'],
      'profile_id': user.id,
      'role': 'owner',
    });

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
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(supabaseClientProvider));
});
