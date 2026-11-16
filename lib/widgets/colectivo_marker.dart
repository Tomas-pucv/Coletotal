import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/puntos_de_sena.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/app_map.dart';

/// Radio base en Modo Radar (1 km): sólo se muestran los colectivos dentro de
/// este radio respecto al usuario y se cargan sus rutas automáticamente.
const double kRadioRutasCercanasKm = 1.0;

/// Radio expandido en Modo Foco (2 km, el doble del radio base): al tocar un
/// vehículo o elegir una línea, se muestran las unidades de esa misma línea
/// dentro de este radio.
const double kRadioLineaSeleccionadaKm = 2.0;

/// Con muchas unidades sólo se dibujan las de este radio alrededor del
/// usuario en vistas generales.
const double kRadioColectivosKm = 6.0;

/// Hasta qué distancia de su línea un colectivo que todavía no se movió se
/// dibuja apuntando como ella. Más lejos no la está recorriendo.
const double kRadioRumboDeLinea = 60;

/// Filtra los colectivos activos según el modo del mapa del pasajero:
/// - En Modo Radar ([recorridoId] es `null`): devuelve sólo las unidades dentro
///   de [radioKm] (por omisión [kRadioRutasCercanasKm] = 1 km) desde [centro].
/// - En Modo Foco ([recorridoId] no es `null`): devuelve sólo las unidades que
///   cubren [recorridoId] dentro de [radioKm] (por omisión
///   [kRadioLineaSeleccionadaKm] = 2 km), además de la unidad [incluirUid] si
///   fue tocada directamente.
List<ColectivoActivo> colectivosEnRadio(
  List<ColectivoActivo> todos,
  LatLng centro, {
  double? radioKm,
  String? recorridoId,
  String? incluirUid,
}) {
  final validos = todos
      .where((c) => !(c.latitud == 0.0 && c.longitud == 0.0))
      .toList(growable: false);
  if (validos.isEmpty) return const [];

  const distance = Distance(roundResult: false);
  final limiteMetros =
      (radioKm ??
          (recorridoId != null
              ? kRadioLineaSeleccionadaKm
              : kRadioRutasCercanasKm)) *
      1000.0;

  return validos
      .where((c) {
        if (recorridoId != null && c.recorridoId != recorridoId) {
          return false;
        }
        if (incluirUid != null && c.uid == incluirUid) {
          return true;
        }
        final metros = distance.as(
          LengthUnit.Meter,
          centro,
          LatLng(c.latitud, c.longitud),
        );
        return metros <= limiteMetros;
      })
      .toList(growable: false);
}

/// Devuelve los [Recorrido]s únicos correspondientes a los [colectivos]
/// cercanos (por ejemplo, los que están dentro de [kRadioRutasCercanasKm]),
/// ordenados desde el colectivo más cercano a [centro] hasta el más lejano.
///
/// Cuando entra un colectivo nuevo al radio se incluye su línea; cuando sale el
/// último colectivo de esa línea, deja de devolverse y desaparece del mapa.
List<Recorrido> recorridosDeColectivos(
  List<ColectivoActivo> colectivos,
  List<Recorrido> disponibles, {
  LatLng? centro,
}) {
  if (colectivos.isEmpty || disponibles.isEmpty) return const [];

  final porId = {for (final r in disponibles) r.id: r};
  final ordenados = colectivos.toList(growable: false);
  if (centro != null && ordenados.length > 1) {
    const distance = Distance();
    ordenados.sort((a, b) {
      final da = distance.as(
        LengthUnit.Meter,
        centro,
        LatLng(a.latitud, a.longitud),
      );
      final db = distance.as(
        LengthUnit.Meter,
        centro,
        LatLng(b.latitud, b.longitud),
      );
      return da.compareTo(db);
    });
  }

  final vistos = <String>{};
  final resultado = <Recorrido>[];
  for (final c in ordenados) {
    final id = c.recorridoId;
    if (id == null || !vistos.add(id)) continue;
    final recorrido = porId[id];
    if (recorrido != null) {
      resultado.add(recorrido);
    }
  }
  return resultado;
}

/// Los colectivos a dibujar: con pocas unidades, todas; con más, sólo las
/// cercanas a [centro], salvo que ninguna lo esté.
List<ColectivoActivo> colectivosVisibles(
  List<ColectivoActivo> todos,
  LatLng centro,
) {
  final validos = todos
      .where((c) => !(c.latitud == 0.0 && c.longitud == 0.0))
      .toList(growable: false);
  if (validos.length <= 4) return validos;
  const distance = Distance();
  final cerca = validos
      .where(
        (c) =>
            distance.as(
              LengthUnit.Kilometer,
              centro,
              LatLng(c.latitud, c.longitud),
            ) <=
            kRadioColectivosKm,
      )
      .toList(growable: false);
  return cerca.isEmpty ? validos : cerca;
}

/// La línea que cubre [colectivo], para su etiqueta: "10 T" y el color de la
/// línea. `null` si el chofer no eligió línea o la línea ya no existe.
({String texto, Color color})? lineaDeColectivo(ColectivoActivo colectivo) {
  final id = colectivo.recorridoId;
  if (id == null) return null;
  final r = RecorridosService.instance.byId(id);
  if (r == null) return null;
  return (texto: PuntosDeSena.etiqueta(r), color: Color(r.colorValue));
}

/// Hacia dónde apunta [colectivo] en el mapa, en grados desde el norte.
///
/// Su rumbo, si ya se movió ([ColectivoActivo.rumbo]). Si no —recién apareció,
/// o espera en la garita—, el de su línea en ese lugar, por el sentido que le
/// pase más cerca: es hacia donde va a salir. Sin línea, al norte.
double rumboDeColectivo(ColectivoActivo colectivo) {
  if (colectivo.rumbo case final rumbo?) return rumbo;
  final id = colectivo.recorridoId;
  final linea = id == null ? null : RecorridosService.instance.byId(id);
  if (linea == null) return 0;
  final aqui = LatLng(colectivo.latitud, colectivo.longitud);
  PuntoEnLinea? mejor;
  for (final (_, trayecto) in linea.trayectos) {
    final cerca = nearestOnPolyline(trayecto.trazado, aqui);
    if (cerca != null &&
        cerca.metros <= kRadioRumboDeLinea &&
        (mejor == null || cerca.metros < mejor.metros)) {
      mejor = cerca;
    }
  }
  return mejor?.rumbo ?? 0;
}

/// El disco bajo el auto es blanco en cualquier tema. Su anillo lleva el color
/// de la línea, y los colores de las líneas son tonos oscuros
/// (`kRecorridoColors`): sobre un disco oscuro, el del tema oscuro, no se
/// distinguían. Es lo mismo que el contorno blanco de los recorridos.
const Color _discoDelAuto = Color(0xFFFFFFFF);

/// Un colectivo en servicio, para el mapa del pasajero, el del chofer y la
/// consola de flota: un auto negro con su letrero amarillo, visto desde
/// arriba, que apunta hacia donde va.
///
/// Con [linea], el anillo que lo rodea es del color de su línea —el mismo de
/// su recorrido en el mapa— y una etiqueta debajo dice cuál es ("10 T"). Sin
/// línea, el anillo es el verde de "en servicio". [selected] es la unidad
/// elegida en la consola de flota: se dibuja más grande.
MapVehicle colectivoMarker(
  ColectivoActivo colectivo, {
  required bool isMe,
  required bool offline,
  required Color primary,
  required AppLocalizations l10n,
  ({String texto, Color color})? linea,
  bool selected = false,
  VoidCallback? onTap,
}) {
  return MapVehicle(
    id: 'colectivo_${colectivo.uid}',
    point: LatLng(colectivo.latitud, colectivo.longitud),
    heading: rumboDeColectivo(colectivo),
    icon: CarIcon(
      bodyColor: kColeTotalInk,
      signColor: kColeTotalYellow,
      ringColor: isMe
          ? primary
          // El verde del tema claro: es el que se lee sobre el disco blanco.
          : (linea?.color.withValues(alpha: 1) ??
                AppStatusColors.light.disponible),
      borderColor: _discoDelAuto,
      diameter: isMe || selected ? 52 : 44,
      tapTarget: AppSpacing.minTapTarget,
    ),
    tag: linea == null
        ? null
        : LineBadge(
            text: linea.texto,
            color: linea.color,
            textColor: AppStatusColors.onColorFor(linea.color),
            borderColor: const Color(0xFFFFFFFF),
          ),
    // Sin señal se atenúa en vez de desaparecer: la unidad existe, pero su
    // posición puede estar desfasada (túnel, cerro sin cobertura).
    opacity: offline ? 0.45 : 1,
    semanticLabel: l10n.colectivoSemanticLabel(
      formatPatente(colectivo.idVehiculo),
      offline
          ? l10n.colectivoNoSignal
          : (colectivo.recorridoNombre ?? l10n.turnoOn),
    ),
    onTap: onTap,
  );
}
