import 'package:flutter_test/flutter_test.dart';
import 'package:taxi1/services/session_log_service.dart';

void main() {
  group('SessionLogService y SessionLogEvent', () {
    test('SessionLogEvent serializa y deserializa preservando datos operacionales', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final evento = SessionLogEvent(
        tipo: 'GPS_LOST',
        timestamp: now,
        datos: {
          'motivo': 'loss_of_satellite_signal',
          'duracion_segundos': 14,
        },
      );

      final map = evento.toMap();
      expect(map['tipo'], equals('GPS_LOST'));
      expect(map['ts'], equals(now));
      expect(map['datos']['duracion_segundos'], equals(14));

      final reconstruido = SessionLogEvent.fromMap(map);
      expect(reconstruido.tipo, equals('GPS_LOST'));
      expect(reconstruido.timestamp, equals(now));
      expect(reconstruido.datos['motivo'], equals('loss_of_satellite_signal'));
    });

    test('SessionLogEvent maneja mapas corruptos o vacíos de forma segura', () {
      final eventoInvalido = SessionLogEvent.fromMap({});
      expect(eventoInvalido.tipo, equals('UNKNOWN'));
      expect(eventoInvalido.datos, isEmpty);
      expect(eventoInvalido.timestamp, isPositive);
    });

    test('SessionLogService registra eventos y mantiene el ciclo de turno', () {
      final logger = SessionLogService.instance;
      expect(logger.hasActiveSession, isFalse);

      logger.logEvent('PRUEBA_EVENTO', {'clave': 'valor'});
      // Debe registrar sin reventar incluso si no hay sesión abierta
      expect(logger.currentSessionId, isNull);
    });
  });
}
