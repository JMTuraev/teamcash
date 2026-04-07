import 'package:intl/intl.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'en_US',
  symbol: 'UZS ',
  decimalDigits: 0,
);

final DateFormat _shortDate = DateFormat('d MMM');
final DateFormat _dateTime = DateFormat('d MMM, HH:mm');

String formatCurrency(int amount) => _money.format(amount);

String formatPercent(int basisPoints) {
  final percentage = basisPoints / 100;
  final decimals = percentage.truncateToDouble() == percentage ? 0 : 2;
  return '${percentage.toStringAsFixed(decimals)}%';
}

String formatShortDate(DateTime date) => _shortDate.format(date.toLocal());

String formatDateTime(DateTime date) => _dateTime.format(date.toLocal());
