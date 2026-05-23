import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';
import 'supabase_client.dart';

/// Read/write access to the `settlements` table. Settlements are explicit
/// payments between two members of a group (e.g. "Aman paid Riya ₹500") that
/// reduce one side's debt. The balance calculator nets them against expenses.
class SettlementsRepository {
  SettlementsRepository(this._client);

  final SupabaseClient _client;

  Future<List<Settlement>> listForGroup(String groupId) async {
    final rows = await _client
        .from('settlements')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Settlement.fromJson)
        .toList();
  }

  /// All settlements visible to the current user — used by the cross-group
  /// balances rollup. RLS already restricts this to groups the user is in.
  Future<List<Settlement>> listAllMine() async {
    final rows = await _client
        .from('settlements')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Settlement.fromJson)
        .toList();
  }
}

final settlementsRepositoryProvider = Provider<SettlementsRepository>((ref) {
  return SettlementsRepository(ref.watch(supabaseClientProvider));
});
