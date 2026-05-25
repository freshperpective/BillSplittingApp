import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../data/activity_repository.dart';
import '../theme/tabby_theme.dart';

/// Reusable row that renders a single [ActivityEvent] — used by both the
/// cross-group Activity tab and the per-group activity sheet on group
/// detail. Pulls profile/group names from a hydrated [ActivityFeed] so it
/// doesn't issue per-row reads.
///
/// Set [showGroupSuffix] to `false` when the surrounding view is already
/// scoped to one group (the per-group sheet), so each row doesn't repeat
/// "in $groupName".
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.event,
    required this.feed,
    required this.myId,
    this.showGroupSuffix = true,
  });

  final ActivityEvent event;
  final ActivityFeed feed;
  final String? myId;
  final bool showGroupSuffix;

  String _personLabel(String id, {bool capitalize = false}) {
    if (id == myId) return capitalize ? 'You' : 'you';
    return feed.profileName(id);
  }

  ({IconData icon, Color tint, String text}) _render() {
    final payload = event.payload;
    final actor = _personLabel(event.actor, capitalize: true);
    final group = feed.groupName(event.groupId);
    final groupSuffix =
        (showGroupSuffix && group.isNotEmpty) ? ' in $group' : '';

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
        final name = (payload['name'] as String?) ?? 'a group';
        final emoji = (payload['emoji'] as String?) ?? '';
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

      case ActivityKind.groupMemberRemove:
        final pid = payload['profile_id'] as String?;
        final selfLeave = payload['self_leave'] == true;
        if (selfLeave) {
          // Actor left on their own. "You left" / "Aman left".
          return (
            icon: Icons.logout,
            tint: TabbyTheme.clay,
            text: '$actor left$groupSuffix',
          );
        }
        final who = pid == null ? 'someone' : _personLabel(pid);
        return (
          icon: Icons.person_remove_outlined,
          tint: TabbyTheme.clay,
          text: '$actor removed $who$groupSuffix',
        );
    }
  }

  /// Tap-throughs where they make sense: an expense event goes to the
  /// expense detail; a settle event goes to the settlement detail (where
  /// the participants can undo it); group events go to the group; the
  /// expense.delete event has no live target so it's not tappable.
  VoidCallback? _onTap(BuildContext context) {
    switch (event.kind) {
      case ActivityKind.expenseAdd:
      case ActivityKind.expenseEdit:
        if (event.groupId == null) return null;
        return () => context.go(
              '/group/${event.groupId}/expense/${event.targetId}',
            );
      case ActivityKind.settle:
        if (event.groupId == null) return null;
        return () => context.go(
              '/group/${event.groupId}/settlement/${event.targetId}',
            );
      case ActivityKind.groupCreate:
      case ActivityKind.groupMemberAdd:
      case ActivityKind.groupMemberRemove:
        if (event.groupId == null) return null;
        return () => context.go('/group/${event.groupId}');
      case ActivityKind.expenseDelete:
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
                      relativeTime(event.createdAt),
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

/// "just now" / "5m ago" / "2h ago" / "yesterday" / "3d ago" / "2w ago" /
/// "Apr 12" — coarse on purpose. The activity feed is a glance surface,
/// not a forensic log.
String relativeTime(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 14) return '${diff.inDays}d ago';
  if (diff.inDays < 60) return '${(diff.inDays / 7).floor()}w ago';
  // Older than two months: dd MMM (yyyy if not this year).
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final mon = months[t.month - 1];
  if (t.year == now.year) return '${t.day} $mon';
  return '${t.day} $mon ${t.year}';
}
