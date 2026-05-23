import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';
import 'supabase_client.dart';

/// A page of activity events plus the lookup tables the UI needs to render
/// them. Profiles and groups are hydrated in one batch read per kind, so the
/// activity tab doesn't issue N+1 queries while scrolling.
class ActivityFeed {
  const ActivityFeed({
    required this.events,
    required this.profileById,
    required this.groupById,
  });

  final List<ActivityEvent> events;
  final Map<String, Profile> profileById;
  final Map<String, Group> groupById;

  String profileName(String id) =>
      profileById[id]?.displayName ?? 'Someone';
  String groupName(String? id) =>
      id == null ? '' : (groupById[id]?.name ?? 'a group');
}

class ActivityRepository {
  ActivityRepository(this._client);

  final SupabaseClient _client;

  /// Most recent [limit] events visible to the current user. RLS already
  /// restricts the rows to groups the user is a member of.
  Future<ActivityFeed> listMine({int limit = 100}) async {
    final rows = await _client
        .from('activity_events')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    final events = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ActivityEvent.fromJson)
        .toList();

    // Gather every profile/group id the renderer might want to name.
    final profileIds = <String>{};
    final groupIds = <String>{};
    for (final e in events) {
      profileIds.add(e.actor);
      if (e.groupId != null) groupIds.add(e.groupId!);

      final fromId = e.payload['from_profile'] as String?;
      final toId = e.payload['to_profile'] as String?;
      final pid = e.payload['profile_id'] as String?;
      if (fromId != null) profileIds.add(fromId);
      if (toId != null) profileIds.add(toId);
      if (pid != null) profileIds.add(pid);
    }

    final profileById = <String, Profile>{};
    if (profileIds.isNotEmpty) {
      final profRows = await _client
          .from('profiles')
          .select('id,display_name,avatar_url,default_currency')
          .inFilter('id', profileIds.toList());
      for (final r in profRows as List) {
        final p = Profile.fromJson((r as Map).cast<String, dynamic>());
        profileById[p.id] = p;
      }
    }

    final groupById = <String, Group>{};
    if (groupIds.isNotEmpty) {
      final groupRows = await _client
          .from('groups')
          .select()
          .inFilter('id', groupIds.toList());
      for (final r in groupRows as List) {
        final g = Group.fromJson((r as Map).cast<String, dynamic>());
        groupById[g.id] = g;
      }
    }

    return ActivityFeed(
      events: events,
      profileById: profileById,
      groupById: groupById,
    );
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(ref.watch(supabaseClientProvider));
});

/// Cross-group activity feed for the current user. Invalidated after mutations
/// that produce activity rows (add-expense, add-member, create-group, settle).
final activityFeedProvider = FutureProvider<ActivityFeed>((ref) async {
  return ref.watch(activityRepositoryProvider).listMine();
});
