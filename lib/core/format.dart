import 'package:intl/intl.dart';

final _thousands = NumberFormat.decimalPattern('es_CL');
final _hour = DateFormat.Hm('es_CL');

/// Formato chileno: $3.490
String formatClp(int amount) => '\$${_thousands.format(amount)}';

String formatPickupWindow(DateTime start, DateTime end) =>
    '${_hour.format(start)} – ${_hour.format(end)}';
