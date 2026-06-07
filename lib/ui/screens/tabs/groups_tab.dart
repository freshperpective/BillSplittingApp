import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/fx_rates.dart';
import '../../../core/models.dart';
import '../../../data/activity_repository.dart';
import '../../../data/groups_repository.dart';
import '../../theme/sorted_theme.dart';

class GroupsTab extends ConsumerWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Groups',
            style: Theme.of(context).textTheme.displaySmall,),
        toolbarHeight: 72,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New group',
            onPressed: () => _showNewGroupSheet(context, ref),
          ),
        ],
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Could not load groups: $e'),
          ),
        ),
        data: (list) {
          if (list.isEmpty) return const _NoGroups();
          // Partition rather than two filter() passes so the ordering from
          // the server (created_at desc) is preserved within each section.
          final active = <Group>[];
          final archived = <Group>[];
          for (final g in list) {
            (g.isArchived ? archived : active).add(g);
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(myGroupsProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No active groups — bring one back from Archived or '
                      'start something new.',
                      style: TextStyle(color: SortedTheme.dimOf(context)),
                    ),
                  )
                else
                  for (final g in active) ...[
                    _GroupCard(group: g),
                    const SizedBox(height: 10),
                  ],
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  // Collapsible so archived groups don't crowd the active list.
                  // Starts collapsed — the count in the title tells the user
                  // what's there without forcing them to scroll past it.
                  ExpansionTile(
                    initiallyExpanded: false,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    childrenPadding: EdgeInsets.zero,
                    // Remove the default top/bottom divider lines.
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: Icon(Icons.archive_outlined,
                        size: 16, color: SortedTheme.dimOf(context),),
                    title: Text(
                      'Archived (${archived.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: SortedTheme.dimOf(context)),
                    ),
                    iconColor: SortedTheme.dimOf(context),
                    collapsedIconColor: SortedTheme.dimOf(context),
                    children: [
                      for (final g in archived) ...[
                        _GroupCard(group: g, archived: true),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showNewGroupSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewGroupSheet(),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, this.archived = false});

  final Group group;

  /// Renders the card in a muted style — same data, lower visual weight.
  /// The actual archive state lives on the Group model; this flag is just
  /// a presentation hint so the Groups tab can group rows by section.
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: SortedTheme.amber.withValues(alpha: archived ? 0.10 : 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(group.emoji, style: const TextStyle(fontSize: 24)),
        ),
        title: Text(group.name,
            style: Theme.of(context).textTheme.titleMedium,),
        subtitle: Row(
          children: [
            Text(group.defaultCurrency,
                style: TextStyle(
                    color: SortedTheme.dimOf(context), fontSize: 12,),),
            if (archived) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2,),
                decoration: BoxDecoration(
                  color: SortedTheme.mist,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('archived',
                    style: TextStyle(
                        color: SortedTheme.dimOf(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,),),
              ),
            ],
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: SortedTheme.dimOf(context)),
        onTap: () => context.go('/group/${group.id}'),
      ),
    );
    return archived ? Opacity(opacity: 0.65, child: card) : card;
  }
}

class _NoGroups extends StatelessWidget {
  const _NoGroups();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined,
                size: 56, color: SortedTheme.teal,),
            const SizedBox(height: 16),
            Text('No groups yet',
                style: Theme.of(context).textTheme.headlineSmall,),
            const SizedBox(height: 8),
            Text(
              'Start a group for the trip, the flat, or the dinner club.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SortedTheme.dimOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewGroupSheet extends ConsumerStatefulWidget {
  const _NewGroupSheet();

  @override
  ConsumerState<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends ConsumerState<_NewGroupSheet> {
  final _name = TextEditingController();
  String _emoji = '💸';
  String _currency = 'INR';
  bool _saving = false;

  static const _emojis = ['💸', '🏖️', '🏠', '🍜', '🎉', '✈️', '⛺'];

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(groupsRepositoryProvider).createGroup(
            name: _name.text.trim(),
            emoji: _emoji,
            defaultCurrency: _currency,
          );
      ref.invalidate(myGroupsProvider);
      // Server-side trigger logs a group.create event — refresh the feed
      // so the new group surfaces in Activity immediately.
      ref.invalidate(activityFeedProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New group', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'e.g. Goa trip',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          Text('Icon', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _emojis
                .map((e) => ChoiceChip(
                      label: Text(e, style: const TextStyle(fontSize: 18)),
                      selected: _emoji == e,
                      onSelected: (_) => setState(() => _emoji = e),
                    ),)
                .toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Default currency'),
            items: FxRates.supported
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _currency = v ?? 'INR'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: SortedTheme.teal,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2,),
                  )
                : const Text('Create group'),
          ),
        ],
      ),
    );
  }
}
