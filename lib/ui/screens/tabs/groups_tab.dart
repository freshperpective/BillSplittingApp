import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../data/groups_repository.dart';
import '../../theme/tabby_theme.dart';

final myGroupsProvider = FutureProvider<List<Group>>((ref) async {
  return ref.watch(groupsRepositoryProvider).listMyGroups();
});

class GroupsTab extends ConsumerWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Groups',
            style: Theme.of(context).textTheme.displaySmall),
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
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(myGroupsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _GroupCard(group: list[i]),
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
  const _GroupCard({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: TabbyTheme.amber.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(group.emoji, style: const TextStyle(fontSize: 24)),
        ),
        title: Text(group.name,
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          group.defaultCurrency,
          style: TextStyle(color: TabbyTheme.dim, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: TabbyTheme.dim),
        onTap: () => context.go('/group/${group.id}'),
      ),
    );
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
                size: 56, color: TabbyTheme.teal),
            const SizedBox(height: 16),
            Text('No groups yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Start a group for the trip, the flat, or the dinner club.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyTheme.dim),
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
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _currency,
            decoration: const InputDecoration(labelText: 'Default currency'),
            items: const ['INR', 'USD', 'EUR', 'GBP', 'JPY']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _currency = v ?? 'INR'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: TabbyTheme.teal,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Create group'),
          ),
        ],
      ),
    );
  }
}
