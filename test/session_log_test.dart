import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi1/services/session_log_service.dart';

const _kActiva = 'coletotal_current_shift_session';
const _kPendientes = 'coletotal_pending_shift_sessions';

void main() {
  final logger = SessionLogService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logger.debugReset();
  });

  Future<void> iniciar() =>
      logger.iniciarSesionTurno(uid: 'u1', patente: 'BBCC12', garitaId: 'g1');

  group('SessionLogEvent', () {
    test('serializa y deserializa preservando datos operacionales', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final evento = SessionLogEvent(
        tipo: 'GPS_LOST',
        timestamp: now,
        datos: {'motivo': 'loss_of_satellite_signal', 'duracion_segundos': 14},
      );

      final reconstruido = SessionLogEvent.fromMap(
        jsonDecode(jsonEncode(evento.toMap())) as Map<String, dynamic>,
      );
      expect(reconstruido.tipo, 'GPS_LOST');
      expect(reconstruido.timestamp, now);
      expect(reconstruido.datos['motivo'], 'loss_of_satellite_signal');
      expect(reconstruido.datos['duracion_segundos'], 14);
    });

    test('maneja mapas corruptos o vacíos de forma segura', () {
      final eventoInvalido = SessionLogEvent.fromMap({});
      expect(eventoInvalido.tipo, 'UNKNOWN');
      expect(eventoInvalido.datos, isEmpty);
      expect(eventoInvalido.timestamp, isPositive);
    });
  });

  group('SessionLogService', () {
    test('sin turno no registra nada', () {
      // Antes los eventos de fuera del turno se acumulaban y terminaban
      // mezclados en la auditoría del turno siguiente.
      logger.logEvent('NETWORK_FAIL', {'error': 'x'});
      expect(logger.hasActiveSession, isFalse);
      expect(logger.debugEventos, isEmpty);
    });

    test('agrupa fallas repetidas en vez de apilarlas', () async {
      await iniciar();
      for (var i = 0; i < 50; i++) {
        logger.logEvent('NETWORK_FAIL', {'error': 'sin red'});
      }

      final fallas = logger.debugEventos
          .where((e) => e.tipo == 'NETWORK_FAIL')
          .toList();
      expect(fallas, hasLength(1));
      expect(fallas.single.datos['repeticiones'], 50);
    });

    test('tiene un tope de eventos por turno', () async {
      // Un documento de Firestore no puede superar 1 MiB: sin tope, un turno
      // largo sin señal no se podía subir nunca.
      await iniciar();
      for (var i = 0; i < SessionLogService.maxEventos + 100; i++) {
        logger.logEvent('STATE_CHANGED', {'i': i});
      }
      expect(
        logger.debugEventos.length,
        lessThanOrEqualTo(SessionLogService.maxEventos),
      );
    });

    test('terminar el turno sin Firebase lo deja en la cola local', () async {
      await iniciar();
      logger.logEvent('STATE_CHANGED', {'estado': 'lleno'});
      await logger.finalizarSesionTurno();

      expect(logger.hasActiveSession, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kActiva), isNull);

      final pendientes = prefs.getStringList(_kPendientes)!;
      expect(pendientes, hasLength(1));
      final payload = jsonDecode(pendientes.single) as Map<String, dynamic>;
      expect(payload['uid'], 'u1');
      expect(payload['garitaId'], 'g1');
      final tipos = (payload['eventos'] as List)
          .map((e) => (e as Map)['tipo'])
          .toList();
      expect(tipos.first, 'SHIFT_START');
      expect(tipos.last, 'SHIFT_END');
    });

    test(
      'recupera el turno de una app que se cerró a mitad de camino',
      () async {
        // El turno en curso se guardaba en el teléfono, pero nadie lo volvía a
        // leer: si Android mataba la app, la jornada se perdía.
        SharedPreferences.setMockInitialValues({
          _kActiva: jsonEncode({
            'sessionId': 'shift_BBCC12_1',
            'uid': 'u1',
            'garitaId': 'g1',
            'inicioTs': 1000,
            'eventos': [
              {'tipo': 'SHIFT_START', 'ts': 1000, 'datos': <String, dynamic>{}},
              {'tipo': 'GPS_LOST', 'ts': 5000, 'datos': <String, dynamic>{}},
            ],
          }),
        });

        await logger.recuperarSesionHuerfana();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kActiva), isNull);
        final pendiente =
            jsonDecode(prefs.getStringList(_kPendientes)!.single)
                as Map<String, dynamic>;
        expect(pendiente['sessionId'], 'shift_BBCC12_1');
        expect(pendiente['interrumpida'], isTrue);
        expect(pendiente['finTs'], 5000);
      },
    );

    test('sin sesión de Firebase no intenta subir pendientes', () async {
      SharedPreferences.setMockInitialValues({
        _kPendientes: [
          jsonEncode({'sessionId': 's1', 'garitaId': 'g1', 'uid': 'u1'}),
        ],
      });

      await logger.sincronizarSesionesPendientes(uid: null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_kPendientes), hasLength(1));
    });
  });
}
