import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/theme/app_colors.dart';

/// Formato y clasificación de distancias/duraciones.
///
/// Unifica tres implementaciones que vivían separadas y podían divergir:
/// `RouteResult.distanceLabel`/`durationLabel` en `route_service.dart`,
/// `_distanceLabel`/`_closenessLabel`/`_closenessColor` en `routes_screen.dart`
/// y `_stopColor` en `map_screen.dart`.
///
/// Además pasa los textos por el ARB, que ya tenía las claves (`distanceKm`,
/// `durationMin`, `veryClose`, …) sin usar.

/// Cercanía de un paradero respecto de la posición del usuario.
enum ProximityBucket {
  /// Sin posición conocida: no se puede afirmar nada sobre la cercanía.
  ///
  /// Antes este caso se colapsaba a `0.0` metros, con lo que la lista de
  /// paraderos mostraba "0 m — Muy cerca" en *todos* con el GPS apagado.
  unknown,
  veryClose,
  close,
  medium,
  far,
}

/// Umbrales en metros, iguales a los que ya usaban ambas pantallas.
const double kVeryCloseMeters = 500;
const double kCloseMeters = 1500;
const double kMediumMeters = 3000;

ProximityBucket proximityOf(double? meters) {
  if (meters == null || !meters.isFinite || meters < 0) {
    return ProximityBucket.unknown;
  }
  if (meters < kVeryCloseMeters) return ProximityBucket.veryClose;
  if (meters < kCloseMeters) return ProximityBucket.close;
  if (meters < kMediumMeters) return ProximityBucket.medium;
  return ProximityBucket.far;
}

Color proximityColor(ProximityBucket bucket, AppStatusColors colors) {
  return switch (bucket) {
    ProximityBucket.unknown => colors.distanceUnknown,
    ProximityBucket.veryClose => colors.distanceVeryClose,
    ProximityBucket.close => colors.distanceClose,
    ProximityBucket.medium => colors.distanceMedium,
    ProximityBucket.far => colors.distanceFar,
  };
}

/// Etiqueta de cercanía, o `null` cuando no hay posición conocida (en ese caso
/// la UI no debe mostrar chip alguno en vez de mentir).
String? proximityLabel(ProximityBucket bucket, AppLocalizations l10n) {
  return switch (bucket) {
    ProximityBucket.unknown => null,
    ProximityBucket.veryClose => l10n.veryClose,
    ProximityBucket.close => l10n.closeDistance,
    ProximityBucket.medium => l10n.mediumDistance,
    ProximityBucket.far => l10n.far,
  };
}

/// Distancia legible: metros bajo 1 km, kilómetros con dos decimales encima.
String formatDistance(double? meters, AppLocalizations l10n) {
  if (meters == null || !meters.isFinite || meters <= 0) return '—';
  if (meters >= 1000) {
    return l10n.distanceKm((meters / 1000).toStringAsFixed(2));
  }
  return l10n.distanceM(meters.toStringAsFixed(0));
}

/// Duración legible a partir de segundos.
String formatDurationSeconds(double? seconds, AppLocalizations l10n) {
  if (seconds == null || !seconds.isFinite || seconds <= 0) return '—';
  final minutes = (seconds / 60).round();
  if (minutes <= 0) return '—';
  if (minutes < 60) return l10n.durationMin('$minutes');
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? l10n.durationHour('$h') : l10n.durationHourMin('$h', '$m');
}

/// Antigüedad legible para "hace X": segundos bajo el minuto, minutos encima.
String formatAgo(Duration age, AppLocalizations l10n) {
  if (age.inSeconds < 60) {
    return l10n.agoSeconds('${age.inSeconds < 0 ? 0 : age.inSeconds}');
  }
  return l10n.agoMinutes('${age.inMinutes}');
}
