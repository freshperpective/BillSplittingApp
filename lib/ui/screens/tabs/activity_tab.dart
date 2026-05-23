import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../data/activity_repository.dart';
import '../../../data/supabase_client.dart';
import '../../theme/tabby_theme.dart';

class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(activityFeedProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Activity',
            style: Theme.of(context).textTheme.displaySmall),
        toolbarHeight: 72,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(activityFeedProvider),
          ),
        ],
      ),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text("Couldn't load activity: $e"),
          ),
        ),
        data: (feed) {
          if (feed.events.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(activityFeedProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: feed.events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ActivityRow(
                event: feed.events[i],
                feed: feed,
                myId: me?.id,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.event,
    required this.feed,
    required this.myId,
  });

  final ActivityEvent event;
  final ActivityFeed feed;
  final String? myId;

  /// Renders the actor's display name, swapping in "You" when it matches the
  /// signed-in user. Used for both the actor and any other profile referenced
  /// in the payload (settlement counterparties, the joined member, etc.).
  String _personLabel(String id, {bool capitalize = false}) {
    if (id == myId) return capitalize ? 'You' : 'you';
    return feed.profileName(id);
  }

  ({IconData icon, Color tint, String text}) _render() {
    final payload = event.payload;
    final actor = _personLabel(event.actor, capitalize: true);
    final group = feed.groupName(event.groupId);
    final groupSuffix = group.isEmpty ? '' : ' in $group';

    switch (event.kind) {
      case ActivityKind.expenseAdd:
        final desc = payload['description'] ?? 'an expense';
        final cur = payload['currency'] ?? '';
        final amt = payload['amount'] ?? '';
        return (
          icon: Icons.add_circle_outline,
          tint: TabbyTheme.teal,
          text: '$actor added "$desc" ($cur $amt)$groupSuffix',
        );

      case ActivityKind.expenseEdit:
        final desc = payload['description'] ?? 'an expense';
        return (
          icon: Icons.edit_outlined,
          tint: TabbyTheme.amber,
          text: '$actor edited "$desc"$groupSuffix',
        );

      case ActivityKind.expenseDelete:
        final desc = payload['description'] ?? 'an expense';
        return (
          icon: Icons.delete_outline,
          tint: TabbyTheme.clay,
          text: '$actor deleted "$desc"$groupSuffix',
        );

      case ActivityKind.settle:
        final cur = payload['currency'] ?? '';
        final amt = payload['amount'] ?? '';
        final fromId = payload['from_profile'] as String?;
        final toId = payload['to_profile'] as String?;
        final fromName = fromId == null ? 'someone' : _personLabel(fromId);
        final toName = toId == null ? 'someone' : _personLabel(toId);
        // If the actor IS the payer, "You paid Riya". Otherwise spell out
        // both sides — useful when a third party logs a payment.
        final text = (fromId != null && fromId == event.actor)
            ? '$actor paid $toName $cur $amt$groupSuffix'
            : '$actor logged $fromName → $toName ($cur $amt)$groupSuffix';
        return (
          icon: Icons.handshake_outlined,
          tint: TabbyTheme.teal,
          text: text,
        );

      case ActivityKind.groupCreate:
        final name = payload['name'] ?? 'a group';
        final emoji = payload['emoji'] ?? '';
        final label = emoji.isEmpty ? name : '$emoji $name';
        return (
          icon: Icons.group_add_outlined,
          tint: TabbyTheme.amber,
          text: '$actor created $label',
        );

      case ActivityKind.groupMemberAdd:
        final pid = payload['profile_id'] as String?;
        final who = pid == null ? 'someone' : _personLabel(pid);
        return (
          icon: Icons.person_add_outlined,
          tint: TabbyTheme.teal,
          text: '$actor added $who$groupSuffix',
        );
    }
  }

  /// Tap-throughs where they make sense: an expense row goes to the expense
  /// detail; everything else does nothing (for now).
  VoidCallback? _onTap(BuildContext context) {
    switch (event.kind) {
      case ActivityKind.expenseAdd:
      case ActivityKind.expenseEdit:
        if (event.groupId == null) return null;
        return () => context.go(
              '/group/${event.groupId}/expense/${event.targetId}',
            );
      case ActivityKind.groupCreate:
      case ActivityKind.groupMemberAdd:
        if (event.groupId == null) return null;
        return () => context.go('/group/${event.groupId}');
      case ActivityKind.expenseDelete:
      case ActivityKind.settle:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _render();
    final tap = _onTap(context);

    return Card(
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: r.tint.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(r.icon, size: 18, color: r.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.text,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      _relativeTime(event.createdAt),
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (tap != null)
                const Icon(Icons.chevron_right,
                    size: 18, color: TabbyTheme.dim),
            ],
          ),
        ),
      ),
    );
  }
}

/// "just now" / "5m ago" / "2h ago" / "yesterday" / "3d ago" / "Apr 12".
///
/// Coarse on purpose — the activity feed is a glance surface, not a forensic
/// log. Past two weeks falls back to month+day; older still includes a year.
String _relativeTime(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 14) return '${diff.inDays}d ago';
  // Older than two weeks: dd MMM (yyyy if not this year).
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final mon = months[t.month - 1];
  if (t.year == now.year) return '${t.day} $mon';
  return '${t.day} $mon ${t.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              child: const Icon(Icons.timeline,
                  size: 36, color: TabbyTheme.amber),
            ),
            const SizedBox(height: 20),
            Text("Nothing's happened yet.",
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Expenses, member adds, and settle-ups will show up here as they happen.',
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
