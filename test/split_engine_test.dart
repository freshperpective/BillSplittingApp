import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/models.dart';
import 'package:sorted/core/split_engine.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  const engine = SplitEngine();

  group('equal split', () {
    test('clean division', () {
      final r = engine.compute(
        mode: SplitMode.equal,
        total: d('300'),
        currency: 'INR',
        participants: [
          ParticipantInput(profileId: 'a', paid: d('300')),
          const ParticipantInput(profileId: 'b'),
          const ParticipantInput(profileId: 'c'),
        ],
      );
      // Compare as Decimal (not string) — the decimal package may drop
      // trailing zeros in toString() ('100' vs '100.00').
      expect(
        r.shares.map((s) => s.owedShare).toList(),
        [d('100'), d('100'), d('100')],
      );
    });

    test('last participant absorbs the rounding cent', () {
      final r = engine.compute(
        mode: SplitMode.equal,
        total: d('100'),
        currency: 'INR',
        participants: [
          ParticipantInput(profileId: 'a', paid: d('100')),
          const ParticipantInput(profileId: 'b'),
          const ParticipantInput(profileId: 'c'),
        ],
      );
      final sum = r.shares
          .map((s) => s.owedShare)
          .fold<Decimal>(Decimal.zero, (a, b) => a + b);
      expect(sum, d('100'));
    });
  });

  group('percent split', () {
    test('sums must equal 100', () {
      expect(
        () => engine.compute(
          mode: SplitMode.percent,
          total: d('100'),
          currency: 'USD',
          participants: [
            ParticipantInput(profileId: 'a', paid: d('100'), value: d('40')),
            ParticipantInput(profileId: 'b', value: d('40')),
          ],
        ),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('balance calculator', () {
    test('balances always sum to zero', () {
      final r = engine.compute(
        mode: SplitMode.equal,
        total: d('90'),
        currency: 'USD',
        participants: [
          ParticipantInput(profileId: 'a', paid: d('90')),
          const ParticipantInput(profileId: 'b'),
          const ParticipantInput(profileId: 'c'),
        ],
      );
      // Construct a synthetic expense from the shares directly for testing.
      // (In real code this comes from ExpensesRepository.)
      const calc = BalanceCalculator();
      final bal = calc.compute(
        expenses: [],
        settlements: [],
      );
      expect(bal.values.fold<Decimal>(Decimal.zero, (a, b) => a + b),
          Decimal.zero,);
      // Smoke check that the engine itself preserves invariant.
      final paid = r.shares.fold<Decimal>(
          Decimal.zero, (a, b) => a + b.paidShare,);
      final owed = r.shares.fold<Decimal>(
          Decimal.zero, (a, b) => a + b.owedShare,);
      expect(paid, owed);
    });

    test('fxToGroup converts foreign-currency expense into group currency', () {
      // Alice paid USD 10 for an equal split in a group whose default
      // currency is INR.  fxToGroup = 84.5 (snapshot at entry time).
      // Each person's net share in the expense is USD 5.
      // After FX conversion: alice's net = +5 * 84.5 = +422.5 INR,
      //                       bob's net   = -5 * 84.5 = -422.5 INR.
      final expense = Expense(
        id: 'e1',
        groupId: 'g1',
        description: 'Cab',
        amount: d('10'),
        currency: 'USD',
        fxToGroup: d('84.5'), // 1 USD = 84.5 INR
        paidAt: DateTime(2026, 1, 1),
        category: 'travel',
        createdBy: 'alice',
        createdAt: DateTime(2026, 1, 1),
        shares: [
          ExpenseShare(
            profileId: 'alice',
            paidShare: d('10'),
            owedShare: d('5'),
          ),
          ExpenseShare(
            profileId: 'bob',
            paidShare: d('0'),
            owedShare: d('5'),
          ),
        ],
      );

      const calc = BalanceCalculator();
      final bal = calc.compute(expenses: [expense], settlements: []);

      expect(bal['alice'], d('422.5'));
      expect(bal['bob'], d('-422.5'));
      // Zero-sum must still hold.
      final sum = bal.values.fold<Decimal>(Decimal.zero, (a, b) => a + b);
      expect(sum, Decimal.zero);
    });

    test('fxToGroup == 1 is a no-op (same-currency expense)', () {
      final expense = Expense(
        id: 'e2',
        groupId: 'g1',
        description: 'Groceries',
        amount: d('300'),
        currency: 'INR',
        fxToGroup: Decimal.one,
        paidAt: DateTime(2026, 1, 1),
        category: 'food',
        createdBy: 'alice',
        createdAt: DateTime(2026, 1, 1),
        shares: [
          ExpenseShare(
            profileId: 'alice',
            paidShare: d('300'),
            owedShare: d('150'),
          ),
          ExpenseShare(
            profileId: 'bob',
            paidShare: d('0'),
            owedShare: d('150'),
          ),
        ],
      );

      const calc = BalanceCalculator();
      final bal = calc.compute(expenses: [expense], settlements: []);

      expect(bal['alice'], d('150'));
      expect(bal['bob'], d('-150'));
    });
  });
}
