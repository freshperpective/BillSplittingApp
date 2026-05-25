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

  /// Owner removes a non-owner member from a group, or a member leaves on
  /// their own. RLS (added in 0007) gates both paths; the activity trigger
  /// writes a `group.member.remove` event. The leaving member loses read
  /// access to the group's data after this returns — their historical
  /// expense_shares stay put so the remaining members' balance math
  /// continues to attribute the debt correctly.
  Future<void> removeMember({
    required String groupId,
    required String profileId,
  }) async {
    // Same RLS-silent-success guard as deleteGroup. If 0007's policy
    // rejects the row (caller isn't owner AND isn't the leaver) PostgREST
    // returns success with zero rows affected; we raise instead.
    final res = await _client
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('profile_id', profileId)
        .select();
    if (res is! List || res.isEmpty) {
      throw Exception(
          'Could not remove this member. Owners can remove non-owners, '
          'and any member can leave on their own — anything else needs '
          'a different action.');
    }
  }

  /// Single group by id. Used by GroupDetailScreen to know whether the
  /// group is archived without re-fetching the whole `myGroupsProvider`
  /// list. RLS already restricts this to groups the user can see.
  Future<Group> getGroup(String id) async {
    final row = await _client
        .from('groups')
        .select()
        .eq('id', id)
        .single();
    return Group.fromJson(row);
  }

  /// Current user's role in the group (`'owner'` | `'member'` | null when
  /// not signed in or not a member). The owner-only menu items hinge on
  /// this; null also covers the not-a-member edge case (RLS would block
  /// the read but maybeSingle returns null cleanly).
  Future<String?> getMyRole(String groupId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('profile_id', user.id)
        .maybeSingle();
    return row?['role'] as String?;
  }

  /// Flip `archived_at` on/off. Archived groups stay visible (just dimmed)
  /// and still count toward balances — this is a soft visibility toggle,
  /// not a debt forgiveness gesture. The UPDATE policy on groups already
  /// limits this to owners.
  Future<void> setArchived({
    required String groupId,
    required bool archived,
  }) async {
    await _client
        .from('groups')
        .update({
          'archived_at': archived
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        })
        .eq('id', groupId);
  }

  /// Permanently delete a group and everything in it (group_members,
  /// expenses, expense_shares via expense FK, settlements, activity_events
  /// — all set up with ON DELETE CASCADE in 0001). The DELETE policy added
  /// in 0004 gates this to owners.
  ///
  /// We chain `.select()` after the delete so PostgREST returns the rows
  /// it actually deleted. If RLS filtered them all out (caller isn't an
  /// owner, or the row's already gone), the result is empty and we raise
  /// instead of returning a misleading success.
  Future<void> deleteGroup(String groupId) async {
    final res = await _client
        .from('groups')
        .delete()
        .eq('id', groupId)
        .select();
    if (res is! List || res.isEmpty) {
      throw Exception(
          'Could not delete this group. You may not have permission, '
          'or it may already be gone.');
    }
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(supabaseClientProvider));
});

// Every per-user provider in this file watches `authStateProvider` so that
// when sign-in / sign-out happens, the cached AsyncValue from the prior
// session doesn't leak into the new one. Without this, a user who was
// previously signed in as the owner would see "owner" cached when they
// later signed in as a different account on the same device.

/// All groups the current user is in, most-recent first.
final myGroupsProvider = FutureProvider<List<Group>>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(groupsRepositoryProvider).listMyGroups();
});

/// Members (profiles) of one group. UI invalidates this after add-member.
final groupMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, groupId) async {
  ref.watch(authStateProvider);
  return ref.watch(groupsRepositoryProvider).listMembers(groupId);
});

/// One group fetched by id. Invalidated after archive/unarchive so the
/// detail screen reflects the new state without a full Groups-tab refresh.
final groupByIdProvider =
    FutureProvider.family<Group, String>((ref, id) async {
  ref.watch(authStateProvider);
  return ref.watch(groupsRepositoryProvider).getGroup(id);
});

/// Current user's role in a given group. `null` means "not a member"
/// (or not signed in). Used to gate owner-only UI affordances.
final myRoleInGroupProvider =
    FutureProvider.family<String?, String>((ref, groupId) async {
  ref.watch(authStateProvider);
  return ref.watch(groupsRepositoryProvider).getMyRole(groupId);
});
