import 'dart:async';

import 'package:flutter/foundation.dart';

/// Qué pasó con una escritura a Firebase.
enum WriteOutcome {
  /// El servidor la confirmó.
  confirmed,

  /// No hubo confirmación a tiempo: quedó en la cola local del SDK y se enviará
  /// sola cuando vuelva la red.
  queuedOffline,
}

/// Espera la confirmación de una escritura, pero no para siempre.
///
/// El `Future` de una escritura de Firestore o Realtime Database se completa
/// recién cuando **el servidor** la confirma. Sin red no falla: se queda
/// esperando. Con caché offline la escritura ya está a salvo en la cola local
/// del SDK, pero quien la esperaba con `await` quedaba colgado: el botón
/// "Fuera de servicio" girando sin fin en un cerro sin cobertura, el cierre de
/// sesión que no cerraba, el administrador sin poder salir del editor.
///
/// Si la confirmación no llega en [timeout] se devuelve
/// [WriteOutcome.queuedOffline] y la escritura sigue su curso sola. Un rechazo
/// que llegue *antes* del plazo (reglas, datos inválidos) se propaga como
/// siempre; uno que llegue *después* solo se registra, porque ya no hay nadie
/// esperándolo y un error asíncrono suelto tumbaría la zona.
Future<WriteOutcome> confirmOrQueue(
  Future<void> write, {
  Duration timeout = const Duration(seconds: 6),
  String? label,
}) async {
  var timedOut = false;
  // Un rechazo anterior al plazo sale por acá como excepción, sin envolver.
  await write.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
    },
  );
  if (!timedOut) return WriteOutcome.confirmed;

  unawaited(
    write.then<void>(
      (_) {},
      onError: (Object e) {
        debugPrint(
          'Escritura${label == null ? '' : ' ($label)'} rechazada después de '
          'encolarse: $e',
        );
      },
    ),
  );
  return WriteOutcome.queuedOffline;
}
