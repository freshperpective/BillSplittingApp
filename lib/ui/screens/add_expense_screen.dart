import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/fx_rates.dart';
import '../../core/models.dart';
import '../../core/split_engine.dart';
import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/sorted_theme.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  /// Both create and edit. When [expenseId] is provided the screen
  /// pre-populates from the existing expense and the save path becomes an
  /// update (atomic via the `update_expense_with_shares` RPC). When null,
  /// it's a brand-new expense.
  const AddExpenseScreen({super.key, required this.groupId, this.expenseId});

  final String groupId;
  final String? expenseId;

  bool get isEditing => expenseId != null;

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

  /// The currency the user has selected for this expense.
  /// Initialised to the group's default currency on first load (see build()).
  String _currency = 'INR';

  /// The group's default currency — kept in sync from the group fetch in
  /// build() so _save() can compute fxToGroup without an extra async call.
  String _groupCurrency = 'INR';

  /// Guards the one-time initialisation of [_currency] for new expenses.
  /// For edits, _prepopulateFrom() sets _currency from the stored expense.
  bool _currencyInitialized = false;

  bool _saving = false;
  String? _error;

  DateTime? _originalPaidAt;
  String? _originalCategory;
  String? _originalNote;

  /// Pre-population guard. The build method runs every frame; we only
  /// want to copy the existing expense into form state once (otherwise
  /// every keystroke would clobber the user's edits).
  bool _prepopulated = false;

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
    final group = ref.watch(groupByIdProvider(widget.groupId));
    // For edit mode: pull from the cached expenses provider. Coming from
    // the detail screen guarantees the cache is warm.
    final expenses = widget.isEditing
        ? ref.watch(groupExpensesProvider(widget.groupId))
        : null;

    // Defensive: archived groups should never reach this screen via the FAB
    // (it's hidden), but route deep-links / hot-reload races could still
    // land us here. Bounce out cleanly instead of letting a save go
    // through that the user already opted to freeze.
    final isArchived = group.valueOrNull?.isArchived ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit expense' : 'New expense'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(),
        ),
      ),
      body: isArchived
          ? _ArchivedNotice(groupId: widget.groupId)
          : members.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed: $e')),
              data: (list) {
                if (widget.isEditing && !_prepopulated) {
                  final expense = expenses?.valueOrNull
                      ?.where((e) => e.id == widget.expenseId)
                      .cast<Expense?>()
                      .firstWhere((_) => true, orElse: () => null);
                  if (expense == null) {
                    // Expense isn't in cache yet — show spinner; the
                    // provider will resolve and rebuild.
                    return const Center(
                        child: CircularProgressIndicator(),);
                  }
                  _prepopulateFrom(expense, list);
                  // _prepopulateFrom sets _prepopulated; fall through.
                }
                _payerId ??=
                    ref.read(currentUserProvider)?.id ?? list.first.id;

                // Sync group currency for FX computation at save time.
                // Also sets the expense currency default for new expenses on
                // first load so the picker opens on the group's currency
                // rather than the hardcoded 'INR' fallback.
                final gc = group.valueOrNull?.defaultCurrency;
                if (gc != null) {
                  _groupCurrency = gc;
                  if (!widget.isEditing && !_currencyInitialized) {
                    _currency = gc;
                    _currencyInitialized = true;
                  }
                }

                return _buildForm(list);
              },
            ),
    );
  }

  /// Navigate back. In edit mode we go to the detail screen we came from;
  /// in create mode, back to the group list. Done via context.go so the
  /// stack stays clean either way.
  void _close() {
    if (widget.isEditing) {
      context.go(
          '/group/${widget.groupId}/expense/${widget.expenseId}',);
    } else {
      context.go('/group/${widget.groupId}');
    }
  }

  /// Copy the existing expense into form state on the first frame where
  /// both members and expense are available. Edit always lands in `adjust`
  /// mode pre-filled with each member's current owed share; the user can
  /// switch modes if they want and the engine will recompute.
  void _prepopulateFrom(Expense exp, List<Profile> members) {
    _description.text = exp.description;
    _amount.text = exp.amount.toString();
    _currency = exp.currency;

    // Pick the largest payer as the primary payer (the create UI assumes
    // a single payer; in practice that's how every expense is created).
    String? primaryPayer;
    Decimal biggest = Decimal.zero;
    for (final s in exp.shares) {
      if (s.paidShare > biggest) {
        biggest = s.paidShare;
        primaryPayer = s.profileId;
      }
    }
    _payerId = primaryPayer ?? members.first.id;

    // Adjust mode: every member's controller gets their current owed
    // share. We don't anchor anyone — the user can edit any field and
    // the engine will rebuild from those amounts.
    _mode = SplitMode.adjust;
    _anchoredMembers.clear();
    final owedByProfile = <String, Decimal>{
      for (final s in exp.shares) s.profileId: s.owedShare,
    };
    for (final m in members) {
      final v = owedByProfile[m.id] ?? Decimal.zero;
      _controllerFor(m.id).text = v.toString();
    }

    _originalPaidAt = exp.paidAt;
    _originalCategory = exp.category;
    _originalNote = exp.note;
    _prepopulated = true;
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
                          decimal: true,),
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration:
                          const InputDecoration(labelText: 'Currency'),
                      items: FxRates.supported
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)),)
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _currency = v ?? _groupCurrency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _payerId,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: members
                    .map((m) => DropdownMenuItem(
                        value: m.id, child: Text(m.displayName),),)
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
                    selectedColor: SortedTheme.teal.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      color:
                          selected ? SortedTheme.teal : SortedTheme.dimOf(context),
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
                    style: const TextStyle(color: SortedTheme.clay),),
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
              backgroundColor: SortedTheme.teal,
              minimumSize: const Size.fromHeight(52),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2,),
                  )
                : Text(widget.isEditing ? 'Save changes' : 'Save expense'),
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

      if (widget.isEditing) {
        // Edit path: atomic RPC replaces row + shares in one transaction.
        // Preserve the original paid-at date — there's no UI for editing
        // it yet, and silently changing it would be surprising.
        await ref.read(expensesRepositoryProvider).update(
              expenseId: widget.expenseId!,
              description: _description.text.trim(),
              amount: total,
              currency: _currency,
              // Recompute the FX snapshot whenever the user edits the expense,
              // even if they didn't change the currency — the rate they get is
              // the same static table value, so it's consistent.
              fxToGroup: FxRates.rate(from: _currency, to: _groupCurrency),
              paidAt: _originalPaidAt ?? DateTime.now(),
              category: _originalCategory ?? 'general',
              note: _originalNote,
              split: split,
            );
      } else {
        await ref.read(expensesRepositoryProvider).create(
              groupId: widget.groupId,
              description: _description.text.trim(),
              amount: total,
              currency: _currency,
              // Snapshot the FX rate at creation time. For same-currency
              // expenses this is 1.0; for foreign-currency ones it's the
              // static mid-market rate from FxRates (until live rates land).
              fxToGroup: FxRates.rate(from: _currency, to: _groupCurrency),
              paidAt: DateTime.now(),
              category: 'general',
              split: split,
            );
      }

      ref.invalidate(groupExpensesProvider(widget.groupId));
      // Balance views (per-group strip + cross-group rollup) cache results
      // off the expense list, so we have to nudge them too.
      ref.invalidate(groupBalanceProvider(widget.groupId));
      ref.invalidate(balancesRollupProvider);
      // Activity feed reads from the server-side trigger row that just landed
      // — bump it so the new event shows up without a manual refresh.
      ref.invalidate(activityFeedProvider);
      ref.invalidate(groupActivityProvider(widget.groupId));

      if (mounted) {
        // After edit, return to the detail screen the user came from.
        // After create, back to the group list.
        if (widget.isEditing) {
          context.go(
              '/group/${widget.groupId}/expense/${widget.expenseId}',);
        } else {
          context.go('/group/${widget.groupId}');
        }
      }
    } catch (e) {
      setState(
          () => _error = e.toString().replaceFirst('Exception: ', ''),);
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
        color: SortedTheme.amber.withValues(alpha: 0.10),
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
                  style: TextStyle(
                      color: SortedTheme.dimOf(context), fontSize: 12,),
                ),
            ],
          ),
          if (isAdjust)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                'Type one to anchor it; the rest re-balance.',
                style: TextStyle(color: SortedTheme.dimOf(context), fontSize: 11),
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
                          size: 14, color: SortedTheme.teal,),
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
                        size: 18, color: SortedTheme.teal,)
                  else
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: controllerFor(m.id),
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true,),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 10,),
                          suffixText: _suffixFor(mode),
                          hintText: '0',
                          filled: true,
                          // Use the theme's card-fill so these inputs
                          // adapt to dark mode (overrides global fillColor).
                          fillColor: SortedTheme.cardFillOf(context),
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
        color: SortedTheme.clay.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: SortedTheme.clay, size: 18,),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: SortedTheme.clay, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the form when the group is archived. Friendly explanation
/// plus a path back to the group page — keeps deep-links / hot-reload races
/// from letting a write through on a frozen group.
class _ArchivedNotice extends StatelessWidget {
  const _ArchivedNotice({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined,
                size: 48, color: SortedTheme.dimOf(context),),
            const SizedBox(height: 12),
            Text('This group is archived.',
                style: Theme.of(context).textTheme.headlineSmall,),
            const SizedBox(height: 8),
            Text(
              'Unarchive it from the group page to add new expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SortedTheme.dimOf(context)),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.go('/group/$groupId'),
              style: FilledButton.styleFrom(
                backgroundColor: SortedTheme.teal,
              ),
              child: const Text('Back to group'),
            ),
          ],
        ),
      ),
    );
  }
}

