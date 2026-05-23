import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../data/balance_providers.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(groupExpensesProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));
    final me = ref.watch(currentUserProvider);
    // Falls back to empty until the members provider resolves — payer name
    // shows up as "Unknown" for the first frame, then settles to the real name.
    final memberList = members.valueOrNull ?? const <Profile>[];

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Group'),
        actions: [
          IconButton(
            tooltip: 'Members',
            icon: const Icon(Icons.people_outline),
            onPressed: () => _openMembersSheet(context, ref, groupId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/group/$groupId/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Column(
        children: [
          // Per-group balance summary lives above the list so the user sees
          // their position before scrolling. Hides itself when there's nothing
          // to say (no expenses yet, or fully settled).
          _GroupBalanceStrip(
            groupId: groupId,
            currentUserId: me?.id,
            members: memberList,
          ),
          Expanded(
            child: expenses.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const _GroupEmpty();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(groupBalanceProvider(groupId));
                    await ref.refresh(
                        groupExpensesProvider(groupId).future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ExpenseRow(
                      expense: list[i],
                      currentUserId: me?.id,
                      members: memberList,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the current user's net position in this group, plus the simplified
/// transfers that involve them ("X owes you ₹Y" / "You owe X ₹Y").
///
/// Renders nothing when there's no data yet, no balance, or the user isn't
/// signed in — so it's safe to drop in unconditionally above the list.
class _GroupBalanceStrip extends ConsumerWidget {
  const _GroupBalanceStrip({
    required this.groupId,
    required this.currentUserId,
    required this.members,
  });

  final String groupId;
  final String? currentUserId;
  final List<Profile> members;

  String _name(String profileId) {
    for (final m in members) {
      if (m.id == profileId) return m.displayName;
    }
    return 'Someone';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = currentUserId;
    if (me == null) return const SizedBox.shrink();

    final balanceAsync = ref.watch(groupBalanceProvider(groupId));

    return balanceAsync.when(
      // Loading: take up no space so the list doesn't jitter on first load.
      loading: () => const SizedBox.shrink(),
      // Errors are silent here — the expense list shows its own error state
      // and the calculator only fails on bad data the server already rejects.
      error: (_, __) => const SizedBox.shrink(),
      data: (balance) {
        final myTransfers = balance.myTransfers(me);
        if (myTransfers.isEmpty) {
          // Either no expenses yet, or everyone's settled. Don't show
          // "All settled" until there's at least one expense — otherwise
          // it crowds the empty state.
          if (balance.netByProfile.isEmpty) return const SizedBox.shrink();
          return _settledChip(context);
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: TabbyTheme.amber.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TabbyTheme.amber.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: myTransfers.map((t) {
              final theyOweMe = t.to == me;
              final otherId = theyOweMe ? t.from : t.to;
              final otherName = _name(otherId);
              final label = theyOweMe
                  ? '$otherName owes you'
                  : 'You owe $otherName';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      theyOweMe ? Icons.south_west : Icons.north_east,
                      size: 16,
                      color: theyOweMe
                          ? TabbyTheme.teal
                          : TabbyTheme.clay,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(fontSize: 14)),
                    ),
                    Text(
                      t.amount.toString(),
                      style: amountStyle(context, positive: theyOweMe)
                          .copyWith(fontSize: 16),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _settledChip(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: TabbyTheme.teal.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TabbyTheme.teal.withOpacity(0.30)),
      ),
      child: Row(
        children: const [
          Icon(Icons.check_circle_outline,
              size: 18, color: TabbyTheme.teal),
          SizedBox(width: 8),
          Text("You're all settled in this group.",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: TabbyTheme.teal)),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.currentUserId,
    required this.members,
  });

  final Expense expense;
  final String? currentUserId;
  final List<Profile> members;

  String _payerLabel() {
    final payers =
        expense.shares.where((s) => s.paidShare > Decimal.zero).toList();
    if (payers.isEmpty) return 'Nobody';
    if (payers.length > 1) return '${payers.length} people';
    final payerId = payers.first.profileId;
    if (payerId == currentUserId) return 'You';
    for (final m in members) {
      if (m.id == payerId) return m.displayName;
    }
    return 'Someone';
  }

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
    final payerLabel = _payerLabel();

    return Card(
      child: ListTile(
        onTap: () => context.go(
            '/group/${expense.groupId}/expense/${expense.id}'),
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
          'Paid by $payerLabel · ${expense.currency} ${expense.amount}',
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

void _openMembersSheet(BuildContext context, WidgetRef ref, String groupId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MembersSheet(groupId: groupId),
  );
}

class _MembersSheet extends ConsumerStatefulWidget {
  const _MembersSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends ConsumerState<_MembersSheet> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  Future<void> _addByEmail() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter a valid email.';
        _success = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    try {
      final repo = ref.read(groupsRepositoryProvider);
      final profile = await repo.findProfileByEmail(email);
      if (profile == null) {
        setState(() => _error =
            'No Tabby account for that email. Ask them to sign up first.');
        return;
      }

      // Don't try to insert if they're already a member — the unique key
      // would 409, but we can give a friendlier message by checking first.
      final current = await ref.read(groupMembersProvider(widget.groupId).future);
      if (current.any((m) => m.id == profile.id)) {
        setState(() => _error = '${profile.displayName} is already in this group.');
        return;
      }

      await repo.addMember(groupId: widget.groupId, profileId: profile.id);
      ref.invalidate(groupMembersProvider(widget.groupId));
      _email.clear();
      setState(() => _success = 'Added ${profile.displayName}.');
    } catch (e) {
      setState(() =>
          _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(widget.groupId));
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Members', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          // Add-by-email row.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Add by email',
                    hintText: 'friend@example.com',
                  ),
                  onSubmitted: (_) => _busy ? null : _addByEmail(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _addByEmail,
                style: FilledButton.styleFrom(
                  backgroundColor: TabbyTheme.teal,
                  minimumSize: const Size(80, 48),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: TabbyTheme.clay, fontSize: 13)),
          ],
          if (_success != null) ...[
            const SizedBox(height: 10),
            Text(_success!,
                style: const TextStyle(color: TabbyTheme.teal, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          Text('In this group',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          members.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load members: $e',
                style: const TextStyle(color: TabbyTheme.clay)),
            data: (list) => Column(
              children: list
                  .map((m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: TabbyTheme.amber.withOpacity(0.4),
                          child: Text(
                            m.displayName.isNotEmpty
                                ? m.displayName.substring(0, 1).toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: TabbyTheme.teal),
                          ),
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(m.defaultCurrency,
                            style: const TextStyle(
                                color: TabbyTheme.dim, fontSize: 12)),
                      ))
                  .toList(),
            ),
          ),
        ],
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
