import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/split_engine.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';
import 'group_detail_screen.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();

  SplitMode _mode = SplitMode.equal;
  String? _payerId;
  String _currency = 'INR';
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('New expense'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/group/${widget.groupId}'),
        ),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed: $e')),
        data: (list) {
          _payerId ??= ref.read(currentUserProvider)?.id ?? list.first.id;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'What was it?',
                    hintText: 'Dinner, taxi, groceries…',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Amount'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _currency,
                        decoration:
                            const InputDecoration(labelText: 'Currency'),
                        items: const ['INR', 'USD', 'EUR', 'GBP', 'JPY']
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _currency = v ?? 'INR'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _payerId,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: list
                      .map((m) => DropdownMenuItem(
                          value: m.id, child: Text(m.displayName)))
                      .toList(),
                  onChanged: (v) => setState(() => _payerId = v),
                ),
                const SizedBox(height: 14),
                Text('Split', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<SplitMode>(
                  segments: const [
                    ButtonSegment(value: SplitMode.equal, label: Text('Equal')),
                    ButtonSegment(
                        value: SplitMode.unequal, label: Text('Unequal')),
                    ButtonSegment(value: SplitMode.percent, label: Text('%')),
                    ButtonSegment(
                        value: SplitMode.shares, label: Text('Shares')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) =>
                      setState(() => _mode = s.first),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: TabbyTheme.clay)),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : () => _save(list),
                  style: FilledButton.styleFrom(
                    backgroundColor: TabbyTheme.teal,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Save expense'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _save(List<Profile> members) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final total = Decimal.parse(_amount.text.trim());
      const engine = SplitEngine();
      // v0.1 supports equal split with single payer. Other modes will be
      // wired up via per-member inputs in v0.2.
      final inputs = members
          .map((m) => ParticipantInput(
                profileId: m.id,
                paid: m.id == _payerId ? total : Decimal.zero,
              ))
          .toList();

      final split = engine.compute(
        mode: SplitMode.equal,
        total: total,
        currency: _currency,
        participants: inputs,
      );

      await ref.read(expensesRepositoryProvider).create(
            groupId: widget.groupId,
            description: _description.text.trim(),
            amount: total,
            currency: _currency,
            fxToGroup: Decimal.one,
            paidAt: DateTime.now(),
            category: 'general',
            split: split,
          );

      // Drop the cached expense list so the group screen re-fetches and
      // the new expense appears immediately.
      ref.invalidate(groupExpensesProvider(widget.groupId));

      if (mounted) context.go('/group/${widget.groupId}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

final _membersProvider =
    FutureProvider.family<List<Profile>, String>((ref, groupId) async {
  return ref.watch(groupsRepositoryProvider).listMembers(groupId);
});
