import 'dart:async';

import 'package:flutter/widgets.dart';

/// Se redibuja cada segundo con el tiempo que falta hasta [until] (nunca negativo).
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.until, required this.builder});

  final DateTime until;
  final Widget Function(BuildContext context, Duration remaining) builder;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    return widget.builder(context, left.isNegative ? Duration.zero : left);
  }
}

/// "12:34" (minutos:segundos).
String formatMmSs(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
