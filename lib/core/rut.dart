/// RUT chileno: valida el dígito verificador (módulo 11) y lo deja como "12.345.678-9".
/// Devuelve null si no es válido.
String? normalizeRut(String input) {
  final clean = input.toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
  if (clean.length < 2) return null;
  final body = clean.substring(0, clean.length - 1);
  final dv = clean.substring(clean.length - 1);
  if (!RegExp(r'^\d{1,8}$').hasMatch(body)) return null;
  var sum = 0, factor = 2;
  for (var i = body.length - 1; i >= 0; i--) {
    sum += int.parse(body[i]) * factor;
    factor = factor == 7 ? 2 : factor + 1;
  }
  final rest = 11 - sum % 11;
  final expected = rest == 11 ? '0' : rest == 10 ? 'K' : '$rest';
  if (dv != expected) return null;
  final digits = int.parse(body).toString();
  final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$grouped-$dv';
}
