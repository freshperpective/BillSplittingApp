import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../theme/tabby_theme.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.groupId,
    required this.expenseId,
  });

  final String groupId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(groupExpensesProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/group/$groupId')),
        title: const Text('Expense'),
      ),
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          final expense = list
              .where((e) => e.id == expenseId)
              .cast<Expense?>()
              .firstWhere((_) => true, orElse: () => null);
          if (expense == null) {
            return const _MissingExpense();
          }
          return members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load members: $e')),
            data: (memberList) => _ExpenseDetailBody(
              expense: expense,
              members: memberList,
            ),
          );
        },
      ),
    );
  }
}

class _ExpenseDetailBody extends StatelessWidget {
  const _ExpenseDetailBody({required this.expense, required this.members});

  final Expense expense;
  final List<Profile> members;

  String _name(String profileId) {
    for (final m in members) {
      if (m.id == profileId) return m.displayName;
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final payerShares =
        expense.shares.where((s) => s.paidShare > Decimal.zero).toList();
    final payerLabel = payerShares.length == 1
        ? _name(payerShares.first.profileId)
        : '${payerShares.length} people';
    final dateFmt = DateFormat.yMMMMd();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Header card: amount, description, date.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TabbyTheme.amber.withOpacity(0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.description,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${expense.currency} ${expense.amount}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: TabbyTheme.teal,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: TabbyTheme.dim),
                  const SizedBox(width: 4),
                  Text('Paid by $payerLabel',
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 13)),
                  const SizedBox(width: 16),
                  const Icon(Icons.event,
                      size: 16, color: TabbyTheme.dim),
                  const SizedBox(width: 4),
                  Text(dateFmt.format(expense.paidAt),
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Breakdown',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        // Per-member rows showing what each person paid and owes.
        ...expense.shares.map((share) {
          final net = share.paidShare - share.owedShare;
          final isPositive = net > Decimal.zero;
          final isZero = net == Decimal.zero;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: TabbyTheme.amber.withOpacity(0.4),
                  child: Text(
                    _name(share.profileId).isNotEmpty
                        ? _name(share.profileId)
                            .substring(0, 1)
                            .toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: TabbyTheme.teal),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name(share.profileId),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        'Owes ${expense.currency} ${share.owedShare}',
                        style: const TextStyle(
                            color: TabbyTheme.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  isZero
                      ? '—'
                      : (isPositive ? '+' : '−') +
                          expense.currency +
                          ' ' +
                          net.abs().toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isZero
                        ? TabbyTheme.dim
                        : (isPositive
                            ? TabbyTheme.teal
                            : TabbyTheme.clay),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _MissingExpense extends StatelessWidget {
  const _MissingExpense();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline,
                size: 48, color: TabbyTheme.dim),
            const SizedBox(height: 12),
            Text("Couldn't find that expense.",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'It may have been deleted. Go back to refresh the list.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}
