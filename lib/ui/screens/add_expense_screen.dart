import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/split_engine.dart';
import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();

  /// Per-member input controllers, keyed by profileId. Created lazily and
  /// disposed when the screen tears down. Semantics vary by mode:
  /// unequal/adjust → amount, percent → 0–100, shares → positive count.
  final Map<String, TextEditingController> _memberInputs = {};

  /// Adjust mode: members whose share the user has explicitly typed. The
  /// remaining (unanchored) members auto-receive `(total - anchoredSum) / n`.
  final Set<String> _anchoredMembers = {};

  /// Guard against the redistribute pass re-triggering onChanged when it
  /// programmatically writes new values into unanchored controllers.
  bool _isRecomputing = false;

  SplitMode _mode = SplitMode.equal;
  String? _payerId;
  String _currency = 'INR';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final c in _memberInputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String profileId) =>
      _memberInputs.putIfAbsent(profileId, () => TextEditingController());

  Decimal? get _amountDecimal {
    final t = _amount.text.trim();
    if (t.isEmpty) return null;
    try {
      final d = Decimal.parse(t);
      return d > Decimal.zero ? d : null;
    } catch (_) {
      return null;
    }
  }

  Decimal _inputAsDecimal(String s) {
    if (s.trim().isEmpty) return Decimal.zero;
    try {
      return Decimal.parse(s.trim());
    } catch (_) {
      return Decimal.zero;
    }
  }

  /// Switch split modes. Entering adjust pre-fills equal shares across
  /// every member and clears the anchor set; leaving adjust just clears
  /// the anchor set so a future re-entry starts fresh.
  void _onModeChange(SplitMode newMode, List<Profile> members) {
    final wasAdjust = _mode == SplitMode.adjust;
    final isAdjust = newMode == SplitMode.adjust;
    setState(() {
      _mode = newMode;
      if (isAdjust && !wasAdjust) {
        _anchoredMembers.clear();
        _redistributeAdjust(members);
      } else if (!isAdjust && wasAdjust) {
        _anchoredMembers.clear();
      }
    });
  }

  void _onAmountChange(List<Profile> members) {
    setState(() {
      if (_mode == SplitMode.adjust) {
        _redistributeAdjust(members);
      }
    });
  }

  /// Handles a user-typed change to a per-member input field. In adjust
  /// mode this anchors the field (if non-empty) or releases it (if empty),
  /// then redistributes the remainder across the unanchored members.
  void _onMemberInputChange(String memberId, List<Profile> members) {
    if (_isRecomputing) return; // programmatic update — don't anchor
    setState(() {
      if (_mode == SplitMode.adjust) {
        final text = _controllerFor(memberId).text.trim();
        if (text.isEmpty) {
          _anchoredMembers.remove(memberId);
        } else {
          _anchoredMembers.add(memberId);
        }
        _redistributeAdjust(members);
      }
    });
  }

  /// Splits `total - anchoredSum` equally across the unanchored members.
  /// Last unanchored member absorbs the rounding remainder so the displayed
  /// fields always sum to exactly `total` (modulo currency rounding).
  void _redistributeAdjust(List<Profile> members) {
    final total = _amountDecimal;
    if (total == null || members.isEmpty) return;

    var anchoredSum = Decimal.zero;
    for (final id in _anchoredMembers) {
      anchoredSum += _inputAsDecimal(_controllerFor(id).text);
    }

    final unanchored = members
        .where((m) => !_anchoredMembers.contains(m.id))
        .toList(growable: false);
    if (unanchored.isEmpty) return;

    final remainder = total - anchoredSum;

    _isRecomputing = true;
    try {
      if (remainder <= Decimal.zero) {
        // Anchored values already exceed (or match) the total — there's
        // nothing left to distribute. The validation banner will explain.
        for (final m in unanchored) {
          _controllerFor(m.id).text = '0';
        }
        return;
      }
      final each = (remainder / Decimal.fromInt(unanchored.length))
          .toDecimal(scaleOnInfinitePrecision: 4)
          .round(scale: 2);
      var running = Decimal.zero;
      for (var i = 0; i < unanchored.length - 1; i++) {
        _controllerFor(unanchored[i].id).text = each.toString();
        running += each;
      }
      _controllerFor(unanchored.last.id).text =
          (remainder - running).toString();
    } finally {
      _isRecomputing = false;
    }
  }

  /// Returns a user-facing validation message for the current per-member
  /// inputs, or null if they validate for the active mode. Returns null
  /// (no banner) when the amount itself isn't entered yet — there's
  /// nothing to validate against.
  String? _validate(List<Profile> members) {
    final total = _amountDecimal;
    if (total == null) return null;

    Decimal sumInputs() => members
        .map((m) => _inputAsDecimal(_controllerFor(m.id).text))
        .fold<Decimal>(Decimal.zero, (a, b) => a + b);

    switch (_mode) {
      case SplitMode.equal:
        return null;
      case SplitMode.unequal:
      case SplitMode.adjust:
        final sum = sumInputs();
        if (sum == total) return null;
        final diff = total - sum;
        return diff > Decimal.zero
            ? '$_currency $diff left to assign'
            : '$_currency ${-diff} over the total';
      case SplitMode.percent:
        final sum = sumInputs();
        final hundred = Decimal.fromInt(100);
        if (sum == hundred) return null;
        final diff = hundred - sum;
        return diff > Decimal.zero ? '$diff% left' : '${-diff}% over';
      case SplitMode.shares:
        final hasAny = members.any(
          (m) => _inputAsDecimal(_controllerFor(m.id).text) > Decimal.zero,
        );
        if (!hasAny) return 'Give at least one person a share';
        return null;
    }
  }

  String _labelFor(SplitMode m) => switch (m) {
        SplitMode.equal => 'Equal',
        SplitMode.unequal => 'Unequal',
        SplitMode.percent => 'Percent',
        SplitMode.shares => 'Shares',
        SplitMode.adjust => 'Adjust',
      };

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(widget.groupId));

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
          return _buildForm(list);
        },
      ),
    );
  }

  Widget _buildForm(List<Profile> members) {
    final validation = _validate(members);
    final canSave = validation == null &&
        _amountDecimal != null &&
        _description.text.trim().isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              TextField(
                controller: _description,
                onChanged: (_) => setState(() {}),
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
                      onChanged: (_) => _onAmountChange(members),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount'),
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
                items: members
                    .map((m) => DropdownMenuItem(
                        value: m.id, child: Text(m.displayName)))
                    .toList(),
                onChanged: (v) => setState(() => _payerId = v),
              ),
              const SizedBox(height: 18),
              Text('Split', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SplitMode.values.map((mode) {
                  final selected = _mode == mode;
                  return ChoiceChip(
                    label: Text(_labelFor(mode)),
                    selected: selected,
                    onSelected: (_) => _onModeChange(mode, members),
                    selectedColor: TabbyTheme.teal.withOpacity(0.18),
                    labelStyle: TextStyle(
                      color:
                          selected ? TabbyTheme.teal : TabbyTheme.dim,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _MemberInputList(
                mode: _mode,
                members: members,
                total: _amountDecimal,
                currency: _currency,
                controllerFor: _controllerFor,
                anchoredMembers: _anchoredMembers,
                onMemberInput: (id) => _onMemberInputChange(id, members),
              ),
              if (validation != null) ...[
                const SizedBox(height: 14),
                _ValidationBanner(message: validation),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: TabbyTheme.clay)),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FilledButton(
            onPressed: (_saving || !canSave) ? null : () => _save(members),
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
        ),
      ],
    );
  }

  Future<void> _save(List<Profile> members) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final total = _amountDecimal!;
      const engine = SplitEngine();

      final inputs = members.map((m) {
        final paid = m.id == _payerId ? total : Decimal.zero;
        final value = _mode == SplitMode.equal
            ? null
            : _inputAsDecimal(_controllerFor(m.id).text);
        return ParticipantInput(
          profileId: m.id,
          paid: paid,
          value: value,
        );
      }).toList();

      final split = engine.compute(
        mode: _mode,
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

      ref.invalidate(groupExpensesProvider(widget.groupId));
      // Balance views (per-group strip + cross-group rollup) cache results
      // off the expense list, so we have to nudge them too.
      ref.invalidate(groupBalanceProvider(widget.groupId));
      ref.invalidate(balancesRollupProvider);
      // Activity feed reads from the server-side trigger row that just landed
      // — bump it so the new event shows up without a manual refresh.
      ref.invalidate(activityFeedProvider);

      if (mounted) context.go('/group/${widget.groupId}');
    } catch (e) {
      setState(
          () => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Renders one row per member with an input that depends on the active
/// split mode. For Equal mode there is no input — we show the calculated
/// per-person share inline as a hint. For Adjust mode we show the same
/// input style as Unequal but highlight rows the user has anchored.
class _MemberInputList extends StatelessWidget {
  const _MemberInputList({
    required this.mode,
    required this.members,
    required this.total,
    required this.currency,
    required this.controllerFor,
    required this.anchoredMembers,
    required this.onMemberInput,
  });

  final SplitMode mode;
  final List<Profile> members;
  final Decimal? total;
  final String currency;
  final TextEditingController Function(String) controllerFor;
  final Set<String> anchoredMembers;
  final void Function(String memberId) onMemberInput;

  String _suffixFor(SplitMode m) => switch (m) {
        SplitMode.percent => '%',
        SplitMode.shares => '',
        SplitMode.unequal => currency,
        SplitMode.adjust => currency,
        SplitMode.equal => '',
      };

  String? _equalSharePreview() {
    if (mode != SplitMode.equal) return null;
    if (total == null || members.isEmpty) return null;
    final each = (total! / Decimal.fromInt(members.length))
        .toDecimal(scaleOnInfinitePrecision: 4)
        .round(scale: 2);
    return '$currency $each each';
  }

  String _headerFor(SplitMode m) => switch (m) {
        SplitMode.equal => 'Split between everyone',
        SplitMode.adjust => 'Adjust per person',
        _ => 'Per-person inputs',
      };

  @override
  Widget build(BuildContext context) {
    final isEqual = mode == SplitMode.equal;
    final isAdjust = mode == SplitMode.adjust;
    final preview = _equalSharePreview();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: TabbyTheme.amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _headerFor(mode),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (preview != null)
                Text(
                  preview,
                  style: const TextStyle(
                      color: TabbyTheme.dim, fontSize: 12),
                ),
            ],
          ),
          if (isAdjust)
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                'Type one to anchor it; the rest re-balance.',
                style: TextStyle(color: TabbyTheme.dim, fontSize: 11),
              ),
            ),
          const SizedBox(height: 4),
          ...members.map((m) {
            final anchored = isAdjust && anchoredMembers.contains(m.id);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  if (anchored)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin,
                          size: 14, color: TabbyTheme.teal),
                    ),
                  Expanded(
                    child: Text(
                      m.displayName,
                      style: TextStyle(
                        fontWeight: anchored
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (isEqual)
                    const Icon(Icons.check,
                        size: 18, color: TabbyTheme.teal)
                  else
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: controllerFor(m.id),
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 10),
                          suffixText: _suffixFor(mode),
                          hintText: '0',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => onMemberInput(m.id),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TabbyTheme.clay.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: TabbyTheme.clay, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: TabbyTheme.clay, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
