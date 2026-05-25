import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/groups_repository.dart';
import '../../data/settlements_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';

/// Detail view for a single settlement. Surfaced from activity rows of
/// kind `settle`. Either party of the payment can hard-delete it; the
/// matching activity row is purged automatically by the 0005 trigger.
class SettlementDetailScreen extends ConsumerWidget {
  const SettlementDetailScreen({
    super.key,
    required this.groupId,
    required this.settlementId,
  });

  final String groupId;
  final String settlementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pull from the group-scoped settlements provider so it stays in sync
    // with whatever the rest of the app shows for this group's balances.
    final settlementsAsync =
        ref.watch(groupSettlementsProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/group/$groupId')),
        title: const Text('Payment'),
      ),
      body: settlementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          final settlement = list
              .where((s) => s.id == settlementId)
              .cast<Settlement?>()
              .firstWhere((_) => true, orElse: () => null);
          if (settlement == null) {
            return const _MissingSettlement();
          }
          return membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load members: $e')),
            data: (memberList) => _SettlementBody(
              settlement: settlement,
              members: memberList,
              myId: me?.id,
            ),
          );
        },
      ),
    );
  }
}

class _SettlementBody extends ConsumerWidget {
  const _SettlementBody({
    required this.settlement,
    required this.members,
    required this.myId,
  });

  final Settlement settlement;
  final List<Profile> members;
  final String? myId;

  String _name(String id) {
    if (id == myId) return 'You';
    for (final m in members) {
      if (m.id == id) return m.displayName;
    }
    return 'Someone';
  }

  bool get _canDelete =>
      myId != null &&
      (settlement.fromProfile == myId || settlement.toProfile == myId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat.yMMMMd().add_jm();
    final from = _name(settlement.fromProfile);
    final to = _name(settlement.toProfile);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TabbyTheme.amber.withOpacity(0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$from → $to',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                '${settlement.currency} ${settlement.amount}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: TabbyTheme.teal,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 14, color: TabbyTheme.dimOf(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Logged ${dateFmt.format(settlement.createdAt.toLocal())}',
                      style: TextStyle(
                          color: TabbyTheme.dimOf(context), fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (settlement.note != null && settlement.note!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: TabbyTheme.cardFillOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: TabbyTheme.borderOf(context)),
                  ),
                  child: Text(settlement.note!,
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_canDelete)
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline, color: TabbyTheme.clay),
            label: const Text('Delete payment',
                style: TextStyle(color: TabbyTheme.clay)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: TabbyTheme.clay),
              minimumSize: const Size.fromHeight(48),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Only the people involved in this payment can remove it.',
              style: TextStyle(color: TabbyTheme.dimOf(context), fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this payment?'),
        content: const Text(
          'The payment will be removed, balances will recalculate, and the '
          'activity feed entry will go with it. This cannot be undone.',
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
      await ref.read(settlementsRepositoryProvider).delete(settlement.id);
      // Settlement gone → balance recalcs; trigger purged the activity row.
      ref.invalidate(groupSettlementsProvider(settlement.groupId));
      ref.invalidate(groupBalanceProvider(settlement.groupId));
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);
      ref.invalidate(groupActivityProvider(settlement.groupId));

      if (context.mounted) {
        context.go('/group/${settlement.groupId}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment deleted.')),
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

class _MissingSettlement extends StatelessWidget {
  const _MissingSettlement();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline,
                size: 48, color: TabbyTheme.dimOf(context)),
            const SizedBox(height: 12),
            Text("Couldn't find that payment.",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'It may have been deleted. Go back to refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyTheme.dimOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
