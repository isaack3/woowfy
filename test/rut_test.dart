import 'package:flutter_test/flutter_test.dart';
import 'package:woowfy/core/rut.dart';

void main() {
  test('RUT válido se normaliza', () {
    expect(normalizeRut('78487341-2'), '78.487.341-2');
    expect(normalizeRut('78.487.341-2'), '78.487.341-2');
    expect(normalizeRut('11.111.111-1'), '11.111.111-1');
    expect(normalizeRut('5.126.663-3'), '5.126.663-3');
  });
  test('RUT con K', () {
    expect(normalizeRut('10.000.013-k'), '10.000.013-K');
  });
  test('RUT inválido', () {
    expect(normalizeRut('78.487.341-3'), isNull);
    expect(normalizeRut('abc'), isNull);
    expect(normalizeRut(''), isNull);
  });
}
