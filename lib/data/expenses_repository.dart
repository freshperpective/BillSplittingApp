import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/split_engine.dart';
import 'supabase_client.dart';

class ExpensesRepository {
  ExpensesRepository(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  Future<List<Expense>> listForGroup(String groupId) async {
    final exps = await _client
        .from('expenses')
        .select()
        .eq('group_id', groupId)
        .isFilter('deleted_at', null)
        .order('paid_at', ascending: false);

    final expIds = (exps as List).map((e) => e['id'] as String).toList();
    if (expIds.isEmpty) {
      return const <Expense>[];
    }

    final shares = await _client
        .from('expense_shares')
        .select()
        .inFilter('expense_id', expIds);

    final sharesByExpense = <String, List<ExpenseShare>>{};
    for (final row in shares as List) {
      final m = (row as Map).cast<String, dynamic>();
      sharesByExpense
          .putIfAbsent(m['expense_id'] as String, () => [])
          .add(ExpenseShare.fromJson(m));
    }

    return exps
        .cast<Map<String, dynamic>>()
        .map((e) => Expense.fromJson(
              e,
              shares: sharesByExpense[e['id'] as String] ?? const [],
            ))
        .toList();
  }

  /// Persists an expense and its shares in a single round trip.
  ///
  /// The split is computed locally via [SplitEngine] before sending, so the
  /// server-side trigger only validates the invariant
  /// `sum(paid_share) == sum(owed_share) == amount`.
  Future<Expense> create({
    required String groupId,
    required String description,
    required Decimal amount,
    required String currency,
    required Decimal fxToGroup,
    required DateTime paidAt,
    required String category,
    String? note,
    required SplitResult split,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    final expenseId = _uuid.v4();

    final expenseRow = {
      'id': expenseId,
      'group_id': groupId,
      'description': description,
      'amount': amount.toString(),
      'currency': currency,
      'fx_to_group': fxToGroup.toString(),
      'paid_at': paidAt.toIso8601String().substring(0, 10),
      'category': category,
      'note': note,
      'created_by': user.id,
    };

    final inserted = await _client
        .from('expenses')
        .insert(expenseRow)
        .select()
        .single();

    final shareRows = split.shares
        .map((s) => {
              'expense_id': expenseId,
              'profile_id': s.profileId,
              'paid_share': s.paidShare.toString(),
              'owed_share': s.owedShare.toString(),
            })
        .toList();

    await _client.from('expense_shares').insert(shareRows);

    return Expense.fromJson(inserted, shares: split.shares);
  }

  Future<void> softDelete(String expenseId) async {
    // `.select()` makes the operation fail loudly when RLS filters us
    // out (caller isn't the creator). Without it the update silently
    // affects zero rows and we'd show a "deleted" snackbar that lied.
    final res = await _client
        .from('expenses')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', expenseId)
        .select();
    if (res is! List || res.isEmpty) {
      throw Exception(
          'Could not delete this expense. Only the creator can.');
    }
  }

  /// Atomic edit. Replaces the expense row's fields AND its shares in one
  /// transaction via the `update_expense_with_shares` RPC — the validate
  /// constraint trigger is deferred so the swap is safe. The RPC enforces
  /// "only the creator can edit" itself, so we don't need to duplicate
  /// that check here.
  Future<void> update({
    required String expenseId,
    required String description,
    required Decimal amount,
    required String currency,
    required Decimal fxToGroup,
    required DateTime paidAt,
    required String category,
    String? note,
    required SplitResult split,
  }) async {
    await _client.rpc('update_expense_with_shares', params: {
      'p_expense_id': expenseId,
      'p_description': description,
      'p_amount': amount.toString(),
      'p_currency': currency,
      'p_fx_to_group': fxToGroup.toString(),
      'p_paid_at': paidAt.toIso8601String().substring(0, 10),
      'p_category': category,
      'p_note': note,
      'p_shares': split.shares
          .map((s) => {
                'profile_id': s.profileId,
                'paid_share': s.paidShare.toString(),
                'owed_share': s.owedShare.toString(),
              })
          .toList(),
    });
  }
}

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref.watch(supabaseClientProvider));
});

/// Expenses for one group, sorted newest-first. UI screens watch this and
/// `ref.invalidate(groupExpensesProvider(groupId))` after mutations.
///
/// Watches `authStateProvider` to drop the cache on sign-out/sign-in so
/// previous-session data doesn't bleed into the new user's view.
final groupExpensesProvider =
    FutureProvider.family<List<Expense>, String>((ref, groupId) async {
  ref.watch(authStateProvider);
  return ref.watch(expensesRepositoryProvider).listForGroup(groupId);
});
