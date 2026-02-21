import 'package:intl/intl.dart';

class FTFormatters {
  const FTFormatters._();

  static final NumberFormat _nairaFormat = NumberFormat.currency(
    locale: 'en_NG',
    symbol: 'NGN ',
    decimalDigits: 0,
  );

  static final NumberFormat _compactNumberFormat = NumberFormat.compact();

  static String naira(num value) => _nairaFormat.format(value);

  static String compact(num value) => _compactNumberFormat.format(value);

  static String date(DateTime value) => DateFormat.yMMMd().format(value);
}
