import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:woowfy/core/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  test('formatea pesos chilenos sin decimales', () {
    expect(formatClp(3990), r'$3.990');
    expect(formatClp(12500), r'$12.500');
  });

  test('formatea ventana de retiro', () {
    final start = DateTime(2026, 10, 1, 19);
    final end = DateTime(2026, 10, 1, 20, 30);
    expect(formatPickupWindow(start, end), '19:00 – 20:30');
  });
}
