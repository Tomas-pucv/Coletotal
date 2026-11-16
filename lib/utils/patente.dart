/// Normalización de patentes chilenas y soporte multi-conductor por vehículo.
///
/// El chofer inicia sesión con su patente, no con un correo (informe §7.3.1-A:
/// "validación de vehículo por patente y su clave personal"), pero Firebase
/// Auth sólo entiende correo + contraseña. La patente se traduce entonces a un
/// correo sintético estable, y por eso la normalización es crítica: `BB-CC-12`,
/// `bbcc12` y `BB CC 12` tienen que llegar al *mismo* correo o el chofer no
/// podrá volver a entrar a su propia cuenta.
///
/// Para soportar que un mismo vehículo (patente) sea conducido por varios
/// choferes (titular, relevo/turno tarde, reemplazo), [patenteToEmail] admite
/// un número de [conductor] (1, 2 o 3). El conductor 1 conserva el correo
/// histórico `<patente>@chofer.coletotal.app` para compatibilidad total, y los
/// conductores adicionales usan `<patente>.c2@...` y `<patente>.c3@...`,
/// manteniendo todos la misma patente en su perfil y en el mapa.
library;

/// Dominio del correo sintético. No es un buzón real y nunca recibe correo:
/// **por eso los choferes no pueden restablecer su contraseña por email**. La
/// recuperación pasa por la garita.
const String kPatenteEmailDomain = 'chofer.coletotal.app';

/// Cantidad máxima de cuentas independientes de chofer por cada patente.
const int kMaxConductoresPorPatente = 3;

/// Quita separadores y pasa a mayúsculas. No valida: para eso está
/// [isValidPatente].
String cleanPatente(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Una patente utilizable: 5 o 6 alfanuméricos con al menos una letra y al
/// menos un dígito.
///
/// Se aceptan 5 caracteres (motos y placas antiguas) en vez de exigir 6: como
/// no hay recuperación de contraseña por correo, rechazar de más deja a un
/// chofer real fuera de la app sin salida.
bool isValidPatente(String raw) {
  final p = cleanPatente(raw);
  if (p.length < 5 || p.length > 6) return false;
  return p.contains(RegExp(r'[A-Z]')) && p.contains(RegExp(r'[0-9]'));
}

/// Correo sintético con el que la patente entra a Firebase Auth.
///
/// [conductor] identifica el cupo de chofer dentro del mismo vehículo (1 por
/// omisión para el titular; 2 o 3 para relevos/turnos adicionales del mismo
/// auto).
///
/// Lanza [ArgumentError] si la patente no es válida, para que un formulario mal
/// validado falle acá y no cree una cuenta imposible de recuperar.
String patenteToEmail(String raw, {int conductor = 1}) {
  final p = cleanPatente(raw);
  if (!isValidPatente(p)) {
    throw ArgumentError.value(raw, 'patente', 'Patente inválida');
  }
  if (conductor < 1 || conductor > kMaxConductoresPorPatente) {
    throw RangeError.range(
      conductor,
      1,
      kMaxConductoresPorPatente,
      'conductor',
    );
  }
  final sufijo = conductor == 1 ? '' : '.c$conductor';
  return '${p.toLowerCase()}$sufijo@$kPatenteEmailDomain';
}

/// Formato de presentación: `BBBB11` -> `BBBB·11`, `AB1234` -> `AB·1234`.
///
/// Separa el bloque de letras del de dígitos para que se lea como una patente y
/// no como una cadena cualquiera.
String formatPatente(String raw) {
  final p = cleanPatente(raw);
  final match = RegExp(r'^([A-Z]+)([0-9]+)$').firstMatch(p);
  if (match == null) return p;
  return '${match.group(1)}·${match.group(2)}';
}
