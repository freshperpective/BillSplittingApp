import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';
import '../widgets/activity_row.dart';
import '../widgets/settle_sheet.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(groupExpensesProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));
    final group = ref.watch(groupByIdProvider(groupId));
    final myRole = ref.watch(myRoleInGroupProvider(groupId));
    final me = ref.watch(currentUserProvider);
    // Falls back to empty until the members provider resolves — payer name
    // shows up as "Unknown" for the first frame, then settles to the real name.
    final memberList = members.valueOrNull ?? const <Profile>[];
    final isArchived = group.valueOrNull?.isArchived ?? false;
    final isOwner = myRole.valueOrNull == 'owner';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: Text(group.valueOrNull?.name ?? 'Group'),
        actions: [
          IconButton(
            tooltip: 'Activity',
            icon: const Icon(Icons.timeline_outlined),
            onPressed: () => _openActivitySheet(context, groupId),
          ),
          IconButton(
            tooltip: 'Members',
            icon: const Icon(Icons.people_outline),
            onPressed: () => _openMembersSheet(context, ref, groupId),
          ),
          // Owner-only menu. Hidden entirely for members so the AppBar
          // doesn't grow an empty kebab for them.
          if (isOwner)
            _OwnerMenu(
              groupId: groupId,
              group: group.valueOrNull,
            ),
        ],
      ),
      // FAB disappears on archived groups — archive = read-only.
      floatingActionButton: isArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/group/$groupId/add'),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      body: Column(
        children: [
          if (isArchived) const _ArchivedBanner(),
          // Group metadata strip — quietly shows who started this and when.
          // Hides itself until the group object loads so we don't render
          // "Created by Someone" placeholder text mid-fetch.
          if (group.valueOrNull != null)
            _GroupMetaLine(
              group: group.value!,
              members: memberList,
              currentUserId: me?.id,
            ),
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

/// Three-dot menu with owner-only actions: archive/unarchive + delete.
/// Lives in the AppBar; the Members button stays separate (open to everyone).
class _OwnerMenu extends ConsumerWidget {
  const _OwnerMenu({required this.groupId, required this.group});

  final String groupId;
  final Group? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArchived = group?.isArchived ?? false;
    return PopupMenuButton<String>(
      tooltip: 'Group actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'archive':
            await _confirmArchive(context, ref, archive: true);
            break;
          case 'unarchive':
            await _confirmArchive(context, ref, archive: false);
            break;
          case 'delete':
            await _confirmDelete(context, ref);
            break;
        }
      },
      itemBuilder: (_) => [
        if (isArchived)
          const PopupMenuItem(
            value: 'unarchive',
            child: Row(children: [
              Icon(Icons.unarchive_outlined, size: 18),
              SizedBox(width: 12),
              Text('Unarchive group'),
            ]),
          )
        else
          const PopupMenuItem(
            value: 'archive',
            child: Row(children: [
              Icon(Icons.archive_outlined, size: 18),
              SizedBox(width: 12),
              Text('Archive group'),
            ]),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: TabbyTheme.clay),
            SizedBox(width: 12),
            Text('Delete group',
                style: TextStyle(color: TabbyTheme.clay)),
          ]),
        ),
      ],
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref, {
    required bool archive,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archive ? 'Archive group?' : 'Bring back this group?'),
        content: Text(
          archive
              ? 'It will become read-only and tuck into the Archived section. '
                  'Balances still count — this just hides the day-to-day.'
              : 'It will move back to your active groups and let you add '
                  'expenses again.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: TabbyTheme.teal),
            child: Text(archive ? 'Archive' : 'Unarchive'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref
          .read(groupsRepositoryProvider)
          .setArchived(groupId: groupId, archived: archive);
      ref.invalidate(groupByIdProvider(groupId));
      ref.invalidate(myGroupsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(archive ? 'Archived.' : 'Brought back.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Couldn't update: $e"),
        ));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // Pull the live balance first — open debts get spelled out in the
    // dialog so the user can't accidentally nuke unsettled history.
    GroupBalance? balance;
    try {
      balance = await ref.read(groupBalanceProvider(groupId).future);
    } catch (_) {
      // If the balance read fails we still let them through, but the
      // dialog falls back to the generic warning.
    }

    final myId = ref.read(currentUserProvider)?.id;
    final myTransfers = (balance != null && myId != null)
        ? balance.myTransfers(myId)
        : const <({String from, String to, Decimal amount})>[];
    final hasOpenDebts = myTransfers.isNotEmpty;

    // Names for the open-debts lines.
    final members =
        ref.read(groupMembersProvider(groupId)).valueOrNull ?? const [];
    String nameOf(String id) {
      if (id == myId) return 'You';
      for (final m in members) {
        if (m.id == id) return m.displayName;
      }
      return 'Someone';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this group?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All expenses, settlements, and history will be permanently '
              'erased. This cannot be undone.',
            ),
            if (hasOpenDebts) ...[
              const SizedBox(height: 12),
              const Text('There are still open balances here:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final t in myTransfers)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    t.to == myId
                        ? '• ${nameOf(t.from)} owes you ${t.amount}'
                        : '• You owe ${nameOf(t.to)} ${t.amount}',
                    style: const TextStyle(
                        color: TabbyTheme.clay, fontSize: 13),
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TabbyTheme.clay),
            child: Text(hasOpenDebts ? 'Delete anyway' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(groupsRepositoryProvider).deleteGroup(groupId);
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);
      if (context.mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group deleted.')),
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

/// Thin metadata strip: "Created by X · MMMM d, yyyy". Lives above the
/// balance strip on the group detail screen so the provenance of the
/// group is one glance away without taking real estate from the list.
class _GroupMetaLine extends StatelessWidget {
  const _GroupMetaLine({
    required this.group,
    required this.members,
    required this.currentUserId,
  });

  final Group group;
  final List<Profile> members;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    // Resolve the creator's display name from the members list. Falls back
    // to "the owner" if the members provider hasn't resolved yet — the line
    // will repaint with the real name once it does.
    String creatorLabel;
    if (group.createdBy == currentUserId) {
      creatorLabel = 'you';
    } else {
      String? name;
      for (final m in members) {
        if (m.id == group.createdBy) {
          name = m.displayName;
          break;
        }
      }
      creatorLabel = name ?? 'the owner';
    }

    final dateFmt = DateFormat.yMMMMd();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: TabbyTheme.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Created by $creatorLabel · ${dateFmt.format(group.createdAt.toLocal())}',
              style: const TextStyle(
                  color: TabbyTheme.dim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: TabbyTheme.mist.withOpacity(0.6),
      child: Row(
        children: const [
          Icon(Icons.archive_outlined, size: 16, color: TabbyTheme.dim),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Archived — read-only. Unarchive to add new expenses.",
              style: TextStyle(color: TabbyTheme.dim, fontSize: 13),
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
    // groupBalanceProvider now carries the group's currency inside
    // GroupBalance.currency, so no separate group watch is needed here.

    return balanceAsync.when(
      // Loading: take up no space so the list doesn't jitter on first load.
      loading: () => const SizedBox.shrink(),
      // Errors are silent here — the expense list shows its own error state
      // and the calculator only fails on bad data the server already rejects.
      error: (_, __) => const SizedBox.shrink(),
      data: (balance) {
        // Either no expenses yet → nothing to show at all.
        if (balance.netByProfile.isEmpty) return const SizedBox.shrink();

        final simplified = ref.watch(simplifyDebtsProvider);
        final decimals = Money.decimalsFor(balance.currency);

        // Shared container decoration used by both views.
        BoxDecoration stripDecoration() => BoxDecoration(
              color: TabbyTheme.amber.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: TabbyTheme.amber.withOpacity(0.35)),
            );

        // Toggle button shown in the top-right corner of the strip.
        // "account_tree" hints at the minimum-transfer graph; "people"
        // hints at showing every member's raw position.
        Widget toggleButton() => Tooltip(
              message: simplified
                  ? 'Show everyone\'s balance'
                  : 'Show simplified transfers',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => ref
                    .read(simplifyDebtsProvider.notifier)
                    .state = !simplified,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    simplified
                        ? Icons.people_outline
                        : Icons.account_tree_outlined,
                    size: 16,
                    color: TabbyTheme.dim,
                  ),
                ),
              ),
            );

        // ── Simplified view (default) ──────────────────────────────────
        // Shows only the transfers that involve the current user so the
        // strip stays focused: "what do YOU need to do in this group?"
        // Each row is tappable to open the settle sheet.
        if (simplified) {
          final myTransfers = balance.myTransfers(me);
          if (myTransfers.isEmpty) return _settledChip(context);

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
            decoration: stripDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: subtle label + toggle affordance.
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your transfers',
                          style: const TextStyle(
                              color: TabbyTheme.dim, fontSize: 11),
                        ),
                      ),
                      toggleButton(),
                    ],
                  ),
                ),
                ...myTransfers.map((t) {
                  final theyOweMe = t.to == me;
                  final otherId = theyOweMe ? t.from : t.to;
                  final otherName = _name(otherId);
                  final label = theyOweMe
                      ? '$otherName owes you'
                      : 'You owe $otherName';
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openSettleSheet(
                      context,
                      fromId: t.from,
                      toId: t.to,
                      fromName: t.from == me ? 'You' : _name(t.from),
                      toName: t.to == me ? 'You' : _name(t.to),
                      amount: t.amount,
                      // balance.currency == group.defaultCurrency;
                      // settlements are always recorded in group currency.
                      currency: balance.currency,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      child: Row(
                        children: [
                          Icon(
                            theyOweMe
                                ? Icons.south_west
                                : Icons.north_east,
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
                            '${balance.currency} '
                            '${t.amount.round(scale: decimals)}',
                            style: amountStyle(context,
                                    positive: theyOweMe)
                                .copyWith(fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.handshake_outlined,
                              size: 16, color: TabbyTheme.dim),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }

        // ── Raw / everyone view ────────────────────────────────────────
        // Shows every member's net position in the group.
        // Positive (teal) = they're owed money; negative (clay) = they owe.
        // Not tappable — there's no unambiguous bilateral settle target.
        final nets = balance.netByProfile.entries
            .where((e) => e.value != Decimal.zero)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value)); // creditors first

        if (nets.isEmpty) return _settledChip(context);

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
          decoration: stripDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Everyone\'s balance',
                        style: const TextStyle(
                            color: TabbyTheme.dim, fontSize: 11),
                      ),
                    ),
                    toggleButton(),
                  ],
                ),
              ),
              ...nets.map((entry) {
                final isCreditor = entry.value > Decimal.zero;
                final isMe = entry.key == me;
                final displayName =
                    isMe ? 'You' : _name(entry.key);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 9),
                  child: Row(
                    children: [
                      Icon(
                        isCreditor
                            ? Icons.south_west
                            : Icons.north_east,
                        size: 16,
                        color: isCreditor
                            ? TabbyTheme.teal
                            : TabbyTheme.clay,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isMe
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      Text(
                        '${balance.currency} '
                        '${entry.value.abs().round(scale: decimals)}',
                        style: amountStyle(context,
                                positive: isCreditor)
                            .copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _openSettleSheet(
    BuildContext context, {
    required String fromId,
    required String toId,
    required String fromName,
    required String toName,
    required Decimal amount,
    required String currency,
  }) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettleSheet(
        groupId: groupId,
        fromProfileId: fromId,
        toProfileId: toId,
        fromName: fromName,
        toName: toName,
        suggestedAmount: amount,
        currency: currency,
      ),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Paid by $payerLabel · ${expense.currency} ${expense.amount}',
              style: const TextStyle(
                  color: TabbyTheme.dim, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              // Distinct from the paidAt-derived day chip — this answers
              // "when did someone log this into the app", useful when an
              // expense gets entered days after the fact.
              'added ${relativeTime(expense.createdAt)}',
              style: const TextStyle(
                  color: TabbyTheme.dim, fontSize: 11),
            ),
          ],
        ),
        isThreeLine: true,
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

void _openActivitySheet(BuildContext context, String groupId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Larger initial height than members — activity is a list that
    // benefits from headroom to scroll.
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) =>
          _GroupActivitySheet(groupId: groupId, scrollController: scrollController),
    ),
  );
}

class _GroupActivitySheet extends ConsumerWidget {
  const _GroupActivitySheet({
    required this.groupId,
    required this.scrollController,
  });

  final String groupId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupActivityProvider(groupId));
    final me = ref.watch(currentUserProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle — drag affordance on top.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: TabbyTheme.mist,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Text('Activity',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () =>
                    ref.invalidate(groupActivityProvider(groupId)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: feedAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text("Couldn't load activity: $e"),
              ),
              data: (feed) {
                if (feed.events.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        "Nothing's happened in this group yet.",
                        style: TextStyle(color: TabbyTheme.dim),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.only(top: 6, bottom: 20),
                  itemCount: feed.events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  // We're already scoped to one group — suppress the
                  // "in $groupName" suffix on each row so it doesn't
                  // repeat for every single event.
                  itemBuilder: (_, i) => ActivityRow(
                    event: feed.events[i],
                    feed: feed,
                    myId: me?.id,
                    showGroupSuffix: false,
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

  /// Self-leave path. Balance-aware: lists any open transfers involving the
  /// current user before letting them go. Closes the sheet and navigates
  /// home on success (the group disappears from their view once RLS kicks
  /// in on the next fetch).
  Future<void> _confirmLeave() async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    await _confirmRemoval(
      profileId: me.id,
      displayName: 'You',
      isSelf: true,
    );
  }

  /// Owner-removes-someone path. Same balance check as leave; the dialog
  /// reads as "X has open balances" instead of "you have open balances".
  Future<void> _confirmRemove({required Profile member}) async {
    await _confirmRemoval(
      profileId: member.id,
      displayName: member.displayName,
      isSelf: false,
    );
  }

  /// Shared confirm + execute path for both Leave and Remove. Pulls the
  /// live balance, lists any open transfers that involve [profileId], and
  /// either asks a normal confirm (when settled) or a sterner one (when
  /// debts are open). On success: invalidate every read that touches
  /// membership, and for self-leave navigate home.
  Future<void> _confirmRemoval({
    required String profileId,
    required String displayName,
    required bool isSelf,
  }) async {
    GroupBalance? balance;
    try {
      balance =
          await ref.read(groupBalanceProvider(widget.groupId).future);
    } catch (_) {
      // Balance read failure isn't fatal — we'll just skip the open-debts
      // section in the dialog and rely on the generic warning.
    }
    final openTransfers = (balance?.transfers ?? const [])
        .where((t) => t.from == profileId || t.to == profileId)
        .toList();
    final hasOpen = openTransfers.isNotEmpty;

    final memberList =
        ref.read(groupMembersProvider(widget.groupId)).valueOrNull ??
            const <Profile>[];
    String nameOf(String id) {
      if (id == profileId) return displayName;
      for (final m in memberList) {
        if (m.id == id) return m.displayName;
      }
      return 'Someone';
    }

    final title = isSelf ? 'Leave this group?' : 'Remove $displayName?';
    final body = isSelf
        ? 'You\'ll lose access to this group. Existing expenses stay '
            'attributed to you so the others\' balances stay correct, '
            'but anything that happens after this won\'t reach you.'
        : '$displayName loses access to the group. Their share of past '
            'expenses stays attributed to them so balances stay correct, '
            'but they won\'t see anything new here.';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            if (hasOpen) ...[
              const SizedBox(height: 12),
              Text(
                isSelf
                    ? 'You still have open balances here:'
                    : '$displayName still has open balances here:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final t in openTransfers)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${nameOf(t.from)} → ${nameOf(t.to)} ${t.amount}',
                    style: const TextStyle(
                        color: TabbyTheme.clay, fontSize: 13),
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TabbyTheme.clay),
            child: Text(hasOpen
                ? (isSelf ? 'Leave anyway' : 'Remove anyway')
                : (isSelf ? 'Leave' : 'Remove')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(groupsRepositoryProvider).removeMember(
            groupId: widget.groupId,
            profileId: profileId,
          );
      ref.invalidate(groupMembersProvider(widget.groupId));
      ref.invalidate(groupBalanceProvider(widget.groupId));
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);
      ref.invalidate(groupActivityProvider(widget.groupId));
      // The leaver no longer sees the group at all — bump the list so it
      // disappears from their groups tab on next look.
      if (isSelf) ref.invalidate(myGroupsProvider);

      if (mounted) {
        Navigator.of(context).pop(); // close the members sheet
        if (isSelf && context.mounted) {
          context.go('/');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Left the group.')),
          );
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed $displayName.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't ${isSelf ? 'leave' : 'remove'}: $e"),
          ),
        );
      }
    }
  }

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
      // New member can change who owes whom in this group, and trips the
      // server-side activity trigger. Bump both surfaces so they reflect it.
      ref.invalidate(groupBalanceProvider(widget.groupId));
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);
      ref.invalidate(groupActivityProvider(widget.groupId));
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
    final group = ref.watch(groupByIdProvider(widget.groupId));
    final isArchived = group.valueOrNull?.isArchived ?? false;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Members', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          // Add-by-email row. Disabled on archived groups — archive = no
          // new state changes; matches the read-only FAB rule on the
          // group detail screen.
          if (isArchived)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                "This group is archived — adding members is paused.",
                style: const TextStyle(
                    color: TabbyTheme.dim, fontSize: 13),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !isArchived,
                  decoration: const InputDecoration(
                    labelText: 'Add by email',
                    hintText: 'friend@example.com',
                  ),
                  onSubmitted: (_) =>
                      (_busy || isArchived) ? null : _addByEmail(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: (_busy || isArchived) ? null : _addByEmail,
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
            data: (list) {
              // Group.createdBy is the source of truth for the owner in v0.3
              // (we don't support transferring ownership yet). When that
              // changes, switch to a role lookup via a members-with-role
              // query instead.
              final ownerId = group.valueOrNull?.createdBy;
              final me = ref.watch(currentUserProvider)?.id;
              final iAmOwner = me != null && me == ownerId;

              return Column(
                children: list.map((m) {
                  final isOwner = m.id == ownerId;
                  final isMe = m.id == me;
                  // Trailing action lives on a row when:
                  //   - it's me, and I'm not the owner (Leave)
                  //   - I'm the owner, and the row is someone else (Remove)
                  // Owner can't be removed; non-owners can't remove peers.
                  final showLeave = isMe && !isOwner;
                  final showRemove = iAmOwner && !isMe;

                  return ListTile(
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
                    title: Row(
                      children: [
                        Flexible(child: Text(m.displayName)),
                        if (isOwner) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: TabbyTheme.teal.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'owner',
                              style: TextStyle(
                                  color: TabbyTheme.teal,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(m.defaultCurrency,
                        style: const TextStyle(
                            color: TabbyTheme.dim, fontSize: 12)),
                    trailing: showLeave
                        ? IconButton(
                            tooltip: 'Leave group',
                            icon: const Icon(Icons.logout,
                                color: TabbyTheme.clay),
                            onPressed: () => _confirmLeave(),
                          )
                        : showRemove
                            ? IconButton(
                                tooltip: 'Remove member',
                                icon: const Icon(Icons.person_remove_outlined,
                                    color: TabbyTheme.clay),
                                onPressed: () =>
                                    _confirmRemove(member: m),
                              )
                            : null,
                  );
                }).toList(),
              );
            },
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

// `relativeTime` is shared from lib/ui/widgets/activity_row.dart.
