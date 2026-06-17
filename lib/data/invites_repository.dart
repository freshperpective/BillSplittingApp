import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

class InvitesRepository {
  InvitesRepository(this._client);
  final SupabaseClient _client;

  /// Creates a single-use invite for [groupId] and returns the 8-char code.
  Future<String> createInvite(String groupId) async {
    final row = await _client
        .from('group_invites')
        .insert({
          'group_id': groupId,
          'created_by': _client.auth.currentUser!.id,
        })
        .select('code')
        .single();
    return row['code'] as String;
  }

  /// Validates [code] server-side and adds the current user to the group.
  /// Returns the group_id they joined.
  Future<String> claimInvite(String code) async {
    final res = await _client.rpc(
      'claim_group_invite',
      params: {'invite_code': code.trim().toUpperCase()},
    );
    return (res as Map<String, dynamic>)['group_id'] as String;
  }
}

final invitesRepositoryProvider = Provider<InvitesRepository>((ref) {
  return InvitesRepository(ref.watch(supabaseClientProvider));
});
