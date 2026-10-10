import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/web_qr.dart';
import '../../data/repository.dart';
import 'redeem_dialog.dart';

/// Modo mostrador: valida retiros uno tras otro con la cámara abierta (web/qr_scanner.js).
/// Fuera de la web, o si el escáner no está disponible, abre el diálogo de siempre.
Future<void> openCounter(BuildContext context, {int? pending}) async {
  if (WebQr.available) {
    final shown = await WebQr.counter(pending: pending, validate: _validate);
    if (shown) return;
  }
  if (context.mounted) await showDialog<void>(context: context, builder: (_) => const RedeemDialog());
}

Future<CounterResult> _validate(String code, bool force) async {
  try {
    final r = await Repository.instance.redeemOrder(code, force: force);
    return (ok: true, title: '1 × ${r.bagTitle}', detail: 'El cliente ya pagó ${formatClp(r.amount)} en línea', retry: false, early: false);
  } on RedeemTooEarly catch (e) {
    return (ok: false, title: 'Aún no es hora', detail: 'Retiro desde las ${e.from} · 1 × ${e.bagTitle}', retry: false, early: true);
  } catch (e) {
    // Código inválido, ya retirado o fuera de horario: hay que frenar la entrega. Lo demás es conexión.
    final stop = e is FirebaseFunctionsException &&
        const {'not-found', 'aborted', 'failed-precondition', 'invalid-argument'}.contains(e.code);
    return (
      ok: false,
      title: stop ? 'No entregues' : 'No se pudo validar',
      detail: friendlyError(e, fallback: 'Revisa tu conexión e intenta de nuevo.'),
      retry: !stop,
      early: false,
    );
  }
}
