import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/split_engine.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';

final _groupMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, groupId) async {
  return ref.watch(groupsRepositoryProvider).listMembers(groupId);
});

final _groupExpensesProvider =
    FutureProvider.family<List<Expense>, String>((ref, groupId) async {
  return ref.watch(expensesRepositoryProvider).listForGroup(groupId);
});

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(_groupExpensesProvider(groupId));
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Group'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/group/$groupId/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const _GroupEmpty();
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(_groupExpensesProvider(groupId).future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ExpenseRow(
                expense: list[i],
                currentUserId: me?.id,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.currentUserId});

  final Expense expense;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.MMMd();
    final yourShare = expense.shares
        .firstWhere(
          (s) => s.profileId == currentUserId,
          orElse: () => ExpenseShare(
            profileId: '',
            paidShare: Decimal.zero,
            owedShare: Decimal.zero,
          ),
        );
    final net = yourShare.paidShare - yourShare.owedShare;
    final youArePositive = net > Decimal.zero;
    final youAreZero = net == Decimal.zero;

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: TabbyTheme.amber.withOpacity(0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            dateFmt.format(expense.paidAt).split(' ').last,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        title: Text(expense.description),
        subtitle: Text(
          '${expense.currency} ${expense.amount}',
          style: TextStyle(color: TabbyTheme.dim, fontSize: 12),
        ),
        trailing: youAreZero
            ? Text('settled',
                style: TextStyle(color: TabbyTheme.dim, fontSize: 12))
            : Text(
                (youArePositive ? '+' : '−') +
                    expense.currency +
                    ' ' +
                    net.abs().toString(),
                style: amountStyle(context, positive: youArePositive),
              ),
      ),
    );
  }
}

class _GroupEmpty extends StatelessWidget {
  const _GroupEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long,
                size: 56, color: TabbyTheme.teal),
            const SizedBox(height: 16),
            Text('No expenses yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to add the first one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}
