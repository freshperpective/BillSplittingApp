import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import 'models.dart';
import 'money.dart';

/// How an expense is divided among participants.
///
/// `adjust` is mathematically identical to `unequal`: the only difference
/// is that the UI pre-fills equal shares and auto-redistributes around
/// fields the user has explicitly anchored. By the time inputs reach the
/// engine they're already per-person amounts.
enum SplitMode { equal, unequal, percent, shares, adjust }

/// Per-participant input for a split.
///
/// - [paid] is how much this profile paid toward the total (`null` = 0).
/// - [value] is the mode-specific input:
///     equal     → ignored
///     unequal   → exact amount owed
///     percent   → percentage (0–100)
///     shares    → integer share count (passed as Decimal for uniformity)
class ParticipantInput {
  const ParticipantInput({
    required this.profileId,
    this.paid,
    this.value,
  });

  final String profileId;
  final Decimal? paid;
  final Decimal? value;
}

class SplitResult {
  const SplitResult(this.shares);
  final List<ExpenseShare> shares;
}

class SplitException implements Exception {
  SplitException(this.message);
  final String message;
  @override
  String toString() => 'SplitException: $message';
}

class SplitEngine {
  const SplitEngine();

  /// Compute owed/paid shares for an expense.
  ///
  /// Invariants checked: every participant appears once; paid totals match
  /// [total]; mode-specific value totals match the expected sum.
  SplitResult compute({
    required SplitMode mode,
    required Decimal total,
    required String currency,
    required List<ParticipantInput> participants,
  }) {
    if (participants.isEmpty) {
      throw SplitException('Need at least one participant');
    }
    final ids = participants.map((p) => p.profileId).toSet();
    if (ids.length != participants.length) {
      throw SplitException('Duplicate participant');
    }
    if (total <= Decimal.zero) {
      throw SplitException('Total must be positive');
    }

    final paidTotal = participants
        .map((p) => p.paid ?? Decimal.zero)
        .fold<Decimal>(Decimal.zero, (a, b) => a + b);
    if (paidTotal != total) {
      throw SplitException(
        'Paid total ($paidTotal) does not equal expense total ($total)',
      );
    }

    final owed = switch (mode) {
      SplitMode.equal => _splitEqual(total, currency, participants),
      SplitMode.unequal => _splitUnequal(total, participants),
      // Adjust uses the same per-person-amounts math as unequal.
      SplitMode.adjust => _splitUnequal(total, participants),
      SplitMode.percent => _splitPercent(total, currency, participants),
      SplitMode.shares => _splitShares(total, currency, participants),
    };

    final shares = <ExpenseShare>[];
    for (final p in participants) {
      shares.add(ExpenseShare(
        profileId: p.profileId,
        paidShare: p.paid ?? Decimal.zero,
        owedShare: owed[p.profileId]!,
      ));
    }
    return SplitResult(shares);
  }

  Map<String, Decimal> _splitEqual(
    Decimal total,
    String currency,
    List<ParticipantInput> ps,
  ) {
    final decimals = Money.decimalsFor(currency);
    final n = ps.length;
    final each = _round(total / Decimal.fromInt(n), decimals);
    final result = <String, Decimal>{};
    Decimal running = Decimal.zero;
    for (var i = 0; i < n - 1; i++) {
      result[ps[i].profileId] = each;
      running += each;
    }
    // Last participant absorbs any rounding remainder.
    result[ps.last.profileId] = total - running;
    return result;
  }

  Map<String, Decimal> _splitUnequal(
    Decimal total,
    List<ParticipantInput> ps,
  ) {
    var sum = Decimal.zero;
    final result = <String, Decimal>{};
    for (final p in ps) {
      final v = p.value;
      if (v == null) {
        throw SplitException('Missing amount for ${p.profileId}');
      }
      result[p.profileId] = v;
      sum += v;
    }
    if (sum != total) {
      throw SplitException('Shares sum to $sum but expense total is $total');
    }
    return result;
  }

  Map<String, Decimal> _splitPercent(
    Decimal total,
    String currency,
    List<ParticipantInput> ps,
  ) {
    final decimals = Money.decimalsFor(currency);
    final hundred = Decimal.fromInt(100);
    var pctSum = Decimal.zero;
    for (final p in ps) {
      if (p.value == null) {
        throw SplitException('Missing percentage for ${p.profileId}');
      }
      pctSum += p.value!;
    }
    if (pctSum != hundred) {
      throw SplitException('Percentages must sum to 100, got $pctSum');
    }

    final result = <String, Decimal>{};
    Decimal running = Decimal.zero;
    for (var i = 0; i < ps.length - 1; i++) {
      final share = _round(
        (total * ps[i].value!) / hundred,
        decimals,
      );
      result[ps[i].profileId] = share;
      running += share;
    }
    result[ps.last.profileId] = total - running;
    return result;
  }

  Map<String, Decimal> _splitShares(
    Decimal total,
    String currency,
    List<ParticipantInput> ps,
  ) {
    final decimals = Money.decimalsFor(currency);
    var shareSum = Decimal.zero;
    for (final p in ps) {
      if (p.value == null || p.value! <= Decimal.zero) {
        throw SplitException('Each participant needs a positive share count');
      }
      shareSum += p.value!;
    }

    final result = <String, Decimal>{};
    Decimal running = Decimal.zero;
    for (var i = 0; i < ps.length - 1; i++) {
      final share = _round((total * ps[i].value!) / shareSum, decimals);
      result[ps[i].profileId] = share;
      running += share;
    }
    result[ps.last.profileId] = total - running;
    return result;
  }

  /// Banker-safe rounding to a fixed number of fractional digits.
  Decimal _round(Rational r, int decimals) {
    return r.toDecimal(scaleOnInfinitePrecision: decimals + 4).round(scale: decimals);
  }
}

/// Net per-profile balance for a group, given its expenses and settlements.
///
/// Positive = others owe this profile. Negative = profile owes others.
/// `Σ balance == 0` by construction.
class BalanceCalculator {
  const BalanceCalculator();

  Map<String, Decimal> compute({
    required List<Expense> expenses,
    required List<Settlement> settlements,
  }) {
    final out = <String, Decimal>{};

    Decimal addTo(String id, Decimal delta) {
      final v = (out[id] ?? Decimal.zero) + delta;
      out[id] = v;
      return v;
    }

    for (final e in expenses) {
      if (e.isDeleted) continue;
      for (final s in e.shares) {
        addTo(s.profileId, s.paidShare - s.owedShare);
      }
    }
    for (final s in settlements) {
      // Money flowed from `from` → `to`; debt of `from` decreased.
      addTo(s.fromProfile, s.amount);
      addTo(s.toProfile, -s.amount);
    }
    return out;
  }

  /// Minimum-transfer reconciliation: given net balances, produce a list of
  /// `(debtor → creditor : amount)` payments that settle everyone.
  ///
  /// Greedy O(n log n) — matches the largest creditor with the largest
  /// debtor each round. Deterministic for equal magnitudes via sort by id.
  List<({String from, String to, Decimal amount})> simplify(
    Map<String, Decimal> balances,
  ) {
    final creditors = <MapEntry<String, Decimal>>[];
    final debtors = <MapEntry<String, Decimal>>[];
    final sortedEntries = balances.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in sortedEntries) {
      if (e.value > Decimal.zero) creditors.add(e);
      if (e.value < Decimal.zero) {
        debtors.add(MapEntry(e.key, -e.value));
      }
    }
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final transfers = <({String from, String to, Decimal amount})>[];
    var i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      final d = debtors[i];
      final c = creditors[j];
      final pay = d.value < c.value ? d.value : c.value;
      transfers.add((from: d.key, to: c.key, amount: pay));
      debtors[i] = MapEntry(d.key, d.value - pay);
      creditors[j] = MapEntry(c.key, c.value - pay);
      if (debtors[i].value == Decimal.zero) i++;
      if (creditors[j].value == Decimal.zero) j++;
    }
    return transfers;
  }
}
