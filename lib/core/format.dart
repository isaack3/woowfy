import 'package:intl/intl.dart';

final _thousands = NumberFormat.decimalPattern('es_CL');
final _hour = DateFormat.Hm('es_CL');
final _shortDate = DateFormat('EEE d MMM', 'es_CL');

/// Formato chileno: $3.490
String formatClp(int amount) => '\$${_thousands.format(amount)}';

String formatPickupWindow(DateTime start, DateTime end) =>
    '${_hour.format(start)} – ${_hour.format(end)}';

/// Día del retiro según la fecha real: "hoy", "mañana", "ayer" o "sáb 10 oct".
String formatPickupDay(DateTime start, {DateTime? now}) {
  final today = _dayOnly(now ?? DateTime.now());
  // Redondeado: el día del cambio de horario dura 23 o 25 horas.
  final diff = (_dayOnly(start).difference(today).inHours / 24).round();
  return switch (diff) {
    0 => 'hoy',
    1 => 'mañana',
    -1 => 'ayer',
    _ => _shortDate.format(start),
  };
}

/// "hoy 18:00 – 19:00". Con [withDate] agrega la fecha a hoy/mañana/ayer: "hoy, sáb 10 oct · 18:00 – 19:00".
String formatPickup(DateTime start, DateTime end, {bool withDate = false, DateTime? now}) {
  final day = formatPickupDay(start, now: now);
  final relative = day == 'hoy' || day == 'mañana' || day == 'ayer';
  if (withDate && relative) return '$day, ${_shortDate.format(start)} · ${formatPickupWindow(start, end)}';
  return '$day ${formatPickupWindow(start, end)}';
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
