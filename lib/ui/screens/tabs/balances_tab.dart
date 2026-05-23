import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/balance_providers.dart';
import '../../../data/supabase_client.dart';
import '../../theme/tabby_theme.dart';

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
                      style: Theme.of(context).textTheme.titleSmall),
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
      BuildContext context, List<PeerBalance> rollup) {
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
        color: TabbyTheme.amber.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your net position',
              style: TextStyle(
                  color: TabbyTheme.dim,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            netZero ? 'Settled up' : net.abs().toString(),
            style:
                Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: netZero
                          ? TabbyTheme.dim
                          : (netPositive
                              ? TabbyTheme.teal
                              : TabbyTheme.clay),
                      fontWeight: FontWeight.w600,
                    ),
          ),
          if (!netZero) ...[
            const SizedBox(height: 4),
            Text(
              netPositive ? 'in your favor' : "you're behind",
              style: const TextStyle(color: TabbyTheme.dim, fontSize: 13),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TabbyTheme.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: TabbyTheme.dim, fontSize: 12)),
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

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.balance});

  final PeerBalance balance;

  @override
  Widget build(BuildContext context) {
    final peerOwes = balance.peerOwesMe;
    final initial = balance.peer.displayName.isNotEmpty
        ? balance.peer.displayName.substring(0, 1).toUpperCase()
        : '?';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: TabbyTheme.amber.withOpacity(0.4),
              child: Text(
                initial,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: TabbyTheme.teal),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(balance.peer.displayName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    peerOwes ? 'owes you' : 'you owe',
                    style: TextStyle(
                      color: peerOwes
                          ? TabbyTheme.teal
                          : TabbyTheme.clay,
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
          ],
        ),
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
                color: TabbyTheme.amber.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.balance,
                  size: 36, color: TabbyTheme.amber),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: TabbyTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}
