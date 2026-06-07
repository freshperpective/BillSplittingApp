import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/balance_providers.dart';
import '../../../data/supabase_client.dart';
import '../../theme/sorted_theme.dart';
import '../../widgets/settle_sheet.dart';

/// Cross-group rollup of who owes whom, from the current user's perspective.
///
/// Currency is treated as a single bucket for v0.2 — the user's default. When
/// we add multi-currency settlements in v0.3 this will need per-currency rows.
class BalancesTab extends ConsumerWidget {
  const BalancesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollupAsync = ref.watch(balancesRollupProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Balances',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        toolbarHeight: 72,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(balancesRollupProvider),
          ),
        ],
      ),
      body: rollupAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text("Couldn't load balances: $e"),
          ),
        ),
        data: (rollup) {
          if (rollup.isEmpty || me == null) {
            return const _EmptyState(
              title: "You're all squared up.",
              subtitle:
                  'When you and a friend share an expense, your balance will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(balancesRollupProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SummaryCard(rollup: rollup),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text('By person',
                      style: Theme.of(context).textTheme.titleSmall,),
                ),
                ..._buildSections(context, rollup),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Owed-to-me first, then owed-by-me. Within each, largest amounts first.
  List<Widget> _buildSections(
      BuildContext context, List<PeerBalance> rollup,) {
    final owedToMe = rollup.where((p) => p.peerOwesMe).toList();
    final iOwe = rollup.where((p) => !p.peerOwesMe).toList();

    return [
      for (final pb in owedToMe) ...[
        _PeerCard(balance: pb),
        const SizedBox(height: 8),
      ],
      if (owedToMe.isNotEmpty && iOwe.isNotEmpty) const SizedBox(height: 8),
      for (final pb in iOwe) ...[
        _PeerCard(balance: pb),
        const SizedBox(height: 8),
      ],
    ];
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.rollup});

  final List<PeerBalance> rollup;

  @override
  Widget build(BuildContext context) {
    var owedToMe = Decimal.zero;
    var iOwe = Decimal.zero;
    for (final p in rollup) {
      if (p.peerOwesMe) {
        owedToMe += p.magnitude;
      } else {
        iOwe += p.magnitude;
      }
    }
    final net = owedToMe - iOwe;
    final netPositive = net > Decimal.zero;
    final netZero = net == Decimal.zero;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SortedTheme.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your net position',
              style: TextStyle(
                  color: SortedTheme.dimOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,),),
          const SizedBox(height: 6),
          Text(
            netZero ? 'Settled up' : net.abs().toString(),
            style:
                Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: netZero
                          ? SortedTheme.dimOf(context)
                          : (netPositive
                              ? SortedTheme.teal
                              : SortedTheme.clay),
                      fontWeight: FontWeight.w600,
                    ),
          ),
          if (!netZero) ...[
            const SizedBox(height: 4),
            Text(
              netPositive ? 'in your favor' : "you're behind",
              style: TextStyle(color: SortedTheme.dimOf(context), fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: 'You are owed',
                  amount: owedToMe,
                  positive: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryStat(
                  label: 'You owe',
                  amount: iOwe,
                  positive: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.amount,
    required this.positive,
  });

  final String label;
  final Decimal amount;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SortedTheme.cardFillOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SortedTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: SortedTheme.dimOf(context), fontSize: 12,),),
          const SizedBox(height: 2),
          Text(
            amount.toString(),
            style: amountStyle(context, positive: positive),
          ),
        ],
      ),
    );
  }
}

class _PeerCard extends ConsumerWidget {
  const _PeerCard({required this.balance});

  final PeerBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerOwes = balance.peerOwesMe;
    final initial = balance.peer.displayName.isNotEmpty
        ? balance.peer.displayName.substring(0, 1).toUpperCase()
        : '?';

    return Card(
      child: InkWell(
        onTap: () => _openBreakdown(context, ref),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: SortedTheme.amber.withValues(alpha: 0.4),
                child: Text(
                  initial,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: SortedTheme.teal,),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(balance.peer.displayName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500,),),
                    const SizedBox(height: 2),
                    Text(
                      peerOwes ? 'owes you' : 'you owe',
                      style: TextStyle(
                        color: peerOwes
                            ? SortedTheme.teal
                            : SortedTheme.clay,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                balance.magnitude.toString(),
                style: amountStyle(context, positive: peerOwes),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 18, color: SortedTheme.dimOf(context),),
            ],
          ),
        ),
      ),
    );
  }

  /// Open the breakdown sheet: shows per-group debts with this peer, lets
  /// the user tap into a group OR open the settle sheet for any one row.
  /// This replaces the earlier "tap = settle" behaviour — settle is still
  /// reachable from each row in the breakdown.
  Future<void> _openBreakdown(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PeerBreakdownSheet(balance: balance),
    );
  }
}

/// Bottom sheet showing a peer's balance broken down by group. Each row
/// tap-navigates to that group; the inline settle icon opens SettleSheet
/// pre-filled with the row's amount.
class _PeerBreakdownSheet extends ConsumerWidget {
  const _PeerBreakdownSheet({required this.balance});

  final PeerBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync =
        ref.watch(peerSettleOptionsProvider(balance.peer.id));
    final me = ref.read(currentUserProvider)?.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: SortedTheme.mist,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header — peer name + signed total, matching the card's tone.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(balance.peer.displayName,
                        style:
                            Theme.of(context).textTheme.headlineSmall,),
                    const SizedBox(height: 2),
                    Text(
                      balance.peerOwesMe ? 'owes you' : 'you owe',
                      style: TextStyle(
                        color: balance.peerOwesMe
                            ? SortedTheme.teal
                            : SortedTheme.clay,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                balance.magnitude.toString(),
                style: amountStyle(context, positive: balance.peerOwesMe)
                    .copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Broken down by group. Tap a row to open it, or use the handshake icon to settle.',
            style: TextStyle(color: SortedTheme.dimOf(context), fontSize: 12),
          ),
          const SizedBox(height: 14),
          optionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text("Couldn't load groups: $e",
                  style: const TextStyle(color: SortedTheme.clay),),
            ),
            data: (options) {
              if (options.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No bilateral group balance with ${balance.peer.displayName}. '
                    'Their debt is routed through someone else by the simplifier — '
                    'settle that link from the group page first.',
                    style: TextStyle(
                        color: SortedTheme.dimOf(context), fontSize: 13,),
                  ),
                );
              }
              return Column(
                children: [
                  for (final o in options)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _BreakdownRow(
                        option: o,
                        peerId: balance.peer.id,
                        peerName: balance.peer.displayName,
                        myId: me,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends ConsumerWidget {
  const _BreakdownRow({
    required this.option,
    required this.peerId,
    required this.peerName,
    required this.myId,
  });

  final PeerSettleOption option;
  final String peerId;
  final String peerName;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerOwesMeHere = option.toProfileId == myId;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Close the sheet first, then navigate. context.go on its own
          // would also work (router replaces stack) but popping makes the
          // back stack cleaner.
          Navigator.of(context).pop();
          context.go('/group/${option.group.id}');
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SortedTheme.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(option.group.emoji,
                    style: const TextStyle(fontSize: 18),),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.group.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,),),
                    const SizedBox(height: 2),
                    Text(
                      peerOwesMeHere
                          ? '$peerName owes you'
                          : 'you owe $peerName',
                      style: TextStyle(
                        color: peerOwesMeHere
                            ? SortedTheme.teal
                            : SortedTheme.clay,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${option.group.defaultCurrency} ${option.amount}',
                style: amountStyle(context, positive: peerOwesMeHere)
                    .copyWith(fontSize: 15),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Settle this debt',
                icon: const Icon(Icons.handshake_outlined, size: 20),
                color: SortedTheme.dimOf(context),
                onPressed: () => _openSettle(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettle(BuildContext context, WidgetRef ref) async {
    String nameFor(String id) {
      if (id == myId) return 'You';
      if (id == peerId) return peerName;
      return 'Someone';
    }

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettleSheet(
        groupId: option.group.id,
        fromProfileId: option.fromProfileId,
        toProfileId: option.toProfileId,
        fromName: nameFor(option.fromProfileId),
        toName: nameFor(option.toProfileId),
        suggestedAmount: option.amount,
        currency: option.group.defaultCurrency,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: SortedTheme.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.balance,
                  size: 36, color: SortedTheme.amber,),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: SortedTheme.dimOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
