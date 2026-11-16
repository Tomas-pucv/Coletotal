import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/services/firestore_writes.dart';

void main() {
  const plazo = Duration(milliseconds: 50);

  group('confirmOrQueue', () {
    test('una escritura confirmada a tiempo es confirmed', () async {
      final outcome = await confirmOrQueue(
        Future<void>.value(),
        timeout: plazo,
      );
      expect(outcome, WriteOutcome.confirmed);
    });

    test('sin confirmación del servidor no se queda esperando', () async {
      // Sin red, el Future de Firestore no se completa nunca: antes eso dejaba
      // colgado el botón "Terminar turno" y el cierre de sesión.
      final nunca = Completer<void>();
      final outcome = await confirmOrQueue(nunca.future, timeout: plazo);
      expect(outcome, WriteOutcome.queuedOffline);
    });

    test('un rechazo antes del plazo se propaga', () async {
      expect(
        confirmOrQueue(
          Future<void>.error(StateError('permission-denied')),
          timeout: plazo,
        ),
        throwsStateError,
      );
    });

    test('un rechazo después del plazo no queda como error suelto', () async {
      // Si quedara sin manejar, el propio test fallaría por error asíncrono.
      final tarde = Completer<void>();
      final outcome = await confirmOrQueue(tarde.future, timeout: plazo);
      expect(outcome, WriteOutcome.queuedOffline);

      tarde.completeError(StateError('rechazada después de encolarse'));
      await Future<void>.delayed(Duration.zero);
    });
  });
}
