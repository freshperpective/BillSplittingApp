import 'package:decimal/decimal.dart';
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

  /// Hard-delete a settlement. Either party can delete (gated by RLS in
  /// migration 0005); the AFTER DELETE trigger purges the matching `settle`
  /// activity row so the feed doesn't keep claiming the payment happened.
  ///
  /// Chains `.select()` to detect RLS-silent-success (PostgREST returns
  /// success even when zero rows were affected). Raises in that case so
  /// the UI doesn't show a misleading "deleted" snackbar.
  Future<void> delete(String id) async {
    final res =
        await _client.from('settlements').delete().eq('id', id).select();
    if (res.isEmpty) {
      throw Exception(
          'Could not delete this payment. Only the people involved can.',);
    }
  }

  /// Record an explicit payment between two members of a group. RLS allows
  /// the insert as long as the caller is `from_profile` or `to_profile` (so
  /// either side of the payment can log it). The server-side trigger writes
  /// the matching activity row, so the caller only has to invalidate read
  /// providers afterwards.
  Future<Settlement> create({
    required String groupId,
    required String fromProfile,
    required String toProfile,
    required Decimal amount,
    required String currency,
    String? note,
  }) async {
    final row = await _client
        .from('settlements')
        .insert({
          'group_id': groupId,
          'from_profile': fromProfile,
          'to_profile': toProfile,
          'amount': amount.toString(),
          'currency': currency,
          'note': note,
        })
        .select()
        .single();
    return Settlement.fromJson(row);
  }
}

final settlementsRepositoryProvider = Provider<SettlementsRepository>((ref) {
  return SettlementsRepository(ref.watch(supabaseClientProvider));
});
