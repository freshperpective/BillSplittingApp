import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// Number of fractional digits per ISO-4217 code.
/// Falls back to 2 if unknown — safe default for most currencies.
const Map<String, int> _currencyDecimals = {
  'JPY': 0,
  'KRW': 0,
  'VND': 0,
  'CLP': 0,
  'BHD': 3,
  'KWD': 3,
  'OMR': 3,
  'TND': 3,
};

class Money {
  Money(this.amount, this.currency);

  factory Money.zero(String currency) => Money(Decimal.zero, currency);

  factory Money.parse(String value, String currency) =>
      Money(Decimal.parse(value), currency);

  final Decimal amount;
  final String currency;

  static int decimalsFor(String currency) =>
      _currencyDecimals[currency.toUpperCase()] ?? 2;

  /// Smallest representable unit for this currency (e.g. 0.01 for USD, 1 for JPY).
  static Decimal minorUnit(String currency) {
    final d = decimalsFor(currency);
    if (d == 0) return Decimal.one;
    return Decimal.parse('1e-$d');
  }

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(amount + other.amount, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(amount - other.amount, currency);
  }

  bool get isZero => amount == Decimal.zero;
  bool get isPositive => amount > Decimal.zero;
  bool get isNegative => amount < Decimal.zero;

  Money abs() => Money(amount.abs(), currency);

  String format({String? locale}) {
    final f = NumberFormat.currency(
      locale: locale,
      name: currency,
      decimalDigits: decimalsFor(currency),
    );
    return f.format(amount.toDouble());
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw StateError(
        'Cannot operate on $currency and ${other.currency} without conversion',
      );
    }
  }

  @override
  String toString() => '$amount $currency';
}
