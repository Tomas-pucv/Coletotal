import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';

/// Etiqueta de la capacidad reportada por el chofer.
///
/// [detallado] agrega la explicación entre paréntesis ("con asientos",
/// "pocos cupos"), que es lo que se muestra en la ficha del colectivo; la
/// versión corta va en listas y en el selector del chofer. Antes la ficha del
/// mapa tenía estos textos escritos a mano, fuera del ARB.
String estadoLabel(
  EstadoCapacidad estado,
  AppLocalizations l10n, {
  bool detallado = false,
}) => switch (estado) {
  EstadoCapacidad.disponible =>
    detallado ? l10n.capacityAvailableLong : l10n.capacityAvailable,
  EstadoCapacidad.medioLleno =>
    detallado ? l10n.capacityHalfLong : l10n.capacityHalf,
  EstadoCapacidad.lleno =>
    detallado ? l10n.capacityFullLong : l10n.capacityFull,
};
