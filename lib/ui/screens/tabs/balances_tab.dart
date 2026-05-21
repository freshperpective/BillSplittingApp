import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/tabby_theme.dart';

class BalancesTab extends ConsumerWidget {
  const BalancesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // v0.1 placeholder. In v0.2 this will roll up balances across all groups
    // by aggregating ExpensesRepository.listForGroup + SettlementsRepository,
    // then running BalanceCalculator.compute over the merged sets per peer.
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Balances',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        toolbarHeight: 72,
      ),
      body: const _EmptyState(
        title: "You're all squared up.",
        subtitle: 'Add a group and an expense to see balances roll in here.',
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
              child: const Icon(Icons.balance, size: 36, color: TabbyTheme.amber),
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
