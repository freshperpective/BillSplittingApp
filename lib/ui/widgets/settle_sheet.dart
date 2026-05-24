import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/settlements_repository.dart';
import '../theme/tabby_theme.dart';

/// Bottom sheet for recording a payment between two members of a group.
///
/// Pre-fills from a known transfer (debtor → creditor : amount). The amount
/// is editable so a user can log partial payments; the from/to chips read
/// like a sentence and aren't swappable inside the sheet — flip the direction
/// in the caller if you need the inverse.
class SettleSheet extends ConsumerStatefulWidget {
  const SettleSheet({
    super.key,
    required this.groupId,
    required this.fromProfileId,
    required this.toProfileId,
    required this.fromName,
    required this.toName,
    required this.suggestedAmount,
    required this.currency,
  });

  final String groupId;
  final String fromProfileId;
  final String toProfileId;
  final String fromName;
  final String toName;
  final Decimal suggestedAmount;
  final String currency;

  @override
  ConsumerState<SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<SettleSheet> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.suggestedAmount.toString());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Decimal? get _parsedAmount {
    final t = _amount.text.trim();
    if (t.isEmpty) return null;
    try {
      final d = Decimal.parse(t);
      return d > Decimal.zero ? d : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final amount = _parsedAmount;
    if (amount == null) {
      setState(() => _error = 'Enter a positive amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(settlementsRepositoryProvider).create(
            groupId: widget.groupId,
            fromProfile: widget.fromProfileId,
            toProfile: widget.toProfileId,
            amount: amount,
            currency: widget.currency,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      // The settle row + activity trigger landed server-side; bump every
      // read surface that depends on settlements.
      ref.invalidate(groupSettlementsProvider(widget.groupId));
      ref.invalidate(groupBalanceProvider(widget.groupId));
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.fromName} → ${widget.toName} '
              '${widget.currency} $amount logged.',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
          Text('Record a payment',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),

          // Direction summary — reads like a sentence so the user can
          // sanity-check who paid whom before tapping Save.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: TabbyTheme.amber.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _personChip(widget.fromName,
                      label: 'From', accent: TabbyTheme.clay),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      size: 18, color: TabbyTheme.dim),
                ),
                Expanded(
                  child: _personChip(widget.toName,
                      label: 'To', accent: TabbyTheme.teal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Amount + currency.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: TabbyTheme.mist),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                child: Text(widget.currency,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'cash, UPI, square-up after Goa…',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: TabbyTheme.clay, fontSize: 13)),
          ],
          const SizedBox(height: 18),
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
                : const Text('Log payment'),
          ),
        ],
      ),
    );
  }

  Widget _personChip(String name, {required String label, required Color accent}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: TabbyTheme.dim, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
