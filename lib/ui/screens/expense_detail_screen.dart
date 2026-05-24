import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
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
    final me = ref.watch(currentUserProvider);

    // Resolve the expense up-front (rather than inside `expenses.when`) so
    // the AppBar can show creator-only actions without nesting another
    // layer of `.when()`.
    final expense = expenses.valueOrNull
        ?.where((e) => e.id == expenseId)
        .cast<Expense?>()
        .firstWhere((_) => true, orElse: () => null);
    final isCreator = expense != null && me?.id == expense.createdBy;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/group/$groupId')),
        title: const Text('Expense'),
        actions: [
          if (isCreator)
            _ExpenseActionsMenu(
              expense: expense,
              groupId: groupId,
            ),
        ],
      ),
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
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

/// Creator-only AppBar actions. Lives as its own widget so the dialog and
/// async flow are encapsulated; the parent screen just decides whether to
/// show it. Today this is just Delete — Edit will join when the design
/// conversation around split-mode round-tripping lands.
class _ExpenseActionsMenu extends ConsumerWidget {
  const _ExpenseActionsMenu({
    required this.expense,
    required this.groupId,
  });

  final Expense expense;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Expense actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        if (v == 'delete') {
          await _confirmDelete(context, ref);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: TabbyTheme.clay),
            SizedBox(width: 12),
            Text('Delete expense',
                style: TextStyle(color: TabbyTheme.clay)),
          ]),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text(
          'It will disappear from the group, balances will recalculate, '
          'and the activity feed will record the removal. '
          'Existing settlements stay put.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TabbyTheme.clay),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(expensesRepositoryProvider).softDelete(expense.id);
      // Server-side trigger logs an expense.delete event automatically;
      // we just need to refresh the read surfaces.
      ref.invalidate(groupExpensesProvider(groupId));
      ref.invalidate(groupBalanceProvider(groupId));
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);
      ref.invalidate(groupActivityProvider(groupId));

      if (context.mounted) {
        context.go('/group/$groupId');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't delete: $e")),
        );
      }
    }
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
    // createdAt vs paidAt are different things: paidAt is the date of the
    // expense itself, createdAt is when it was logged into Tabby. Both are
    // useful in audits ("was this entered late?") so we show both.
    final createdFmt = DateFormat.yMMMd().add_jm();

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
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule_outlined,
                      size: 14, color: TabbyTheme.dim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Added ${createdFmt.format(expense.createdAt.toLocal())} '
                      'by ${_name(expense.createdBy)}',
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 12),
                    ),
                  ),
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
