import 'package:decimal/decimal.dart';

/// Static FX snapshot table for MVP multi-currency support.
///
/// Rates are approximate mid-market values as of 2026-05 and are used as the
/// "entry-time snapshot" written into `fx_to_group` on each expense row.  Once
/// written the snapshot is fixed — balance math never re-fetches.  Live rates
/// from an Edge Function are a post-launch feature.
///
/// All rates are expressed as units-of-currency per 1 USD so any pair can be
/// derived by division without a separate n² table.
class FxRates {
  FxRates._(); // static-only

  /// Units of each currency that equal 1 USD (mid-market, 2026-05 snapshot).
  static final Map<String, Decimal> _perUsd = {
    'USD': Decimal.one,
    'EUR': Decimal.parse('0.92'),
    'GBP': Decimal.parse('0.79'),
    'INR': Decimal.parse('84.50'),
    'JPY': Decimal.parse('155.00'),
    'AUD': Decimal.parse('1.54'),
    'CAD': Decimal.parse('1.37'),
    'SGD': Decimal.parse('1.35'),
    'CHF': Decimal.parse('0.89'),
    'HKD': Decimal.parse('7.79'),
    'AED': Decimal.parse('3.67'),
    'MXN': Decimal.parse('17.10'),
    'THB': Decimal.parse('35.50'),
    'MYR': Decimal.parse('4.72'),
  };

  /// All currencies the app allows on an expense (drives the currency picker).
  static const List<String> supported = [
    'USD', 'EUR', 'GBP', 'INR', 'JPY',
    'AUD', 'CAD', 'SGD', 'CHF', 'HKD',
    'AED', 'MXN', 'THB', 'MYR',
  ];

  /// Snapshot exchange rate: how many units of [to] are in one unit of [from].
  ///
  /// Returns [Decimal.one] for same-currency pairs and for any currency not yet
  /// in the table — a safe fallback that keeps single-currency balance math
  /// identical to before.
  ///
  /// Precision: 8 decimal places, which is well above the 2–3 that balance
  /// display ever shows. Rounding at display time (via [Money.decimalsFor])
  /// removes the trailing digits before the user sees them.
  static Decimal rate({required String from, required String to}) {
    if (from == to) return Decimal.one;
    final fromRate = _perUsd[from];
    final toRate = _perUsd[to];
    // Unknown currency → 1:1 so existing single-currency behaviour is preserved.
    if (fromRate == null || toRate == null) return Decimal.one;
    // 1 [from] → (1 / fromRate) USD → (toRate / fromRate) [to].
    return (toRate / fromRate)
        .toDecimal(scaleOnInfinitePrecision: 8)
        .round(scale: 8);
  }
}
