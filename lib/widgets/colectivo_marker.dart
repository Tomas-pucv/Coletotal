import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/services/puntos_de_sena.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/utils/estado_format.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/app_map.dart';

/// Con muchas unidades sólo se dibujan las de este radio alrededor del
/// usuario (o del centro de Quilpué si no hay posición).
const double kRadioColectivosKm = 6.0;

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

/// El marcador de un colectivo en servicio, para el mapa del pasajero y el del
/// chofer. Con [linea], una etiqueta debajo dice qué línea es ("10 T"), sin
/// tener que dibujar los recorridos.
MapMarker colectivoMarker(
  ColectivoActivo colectivo, {
  required bool isMe,
  required bool offline,
  required AppStatusColors status,
  required Color primary,
  required AppLocalizations l10n,
  ({String texto, Color color})? linea,
  VoidCallback? onTap,
}) {
  // Semaforización de capacidad (informe §7.3.1-C): el color lo reporta el
  // chofer desde su pantalla de turno.
  final color = isMe ? primary : status.forEstado(colectivo.estado);
  final circulo = MarkerIcon.circle(
    diameter: isMe ? 46 : 40,
    color: color,
    borderColor: status.markerBorder,
    borderWidth: isMe ? 3 : 2,
    glyph: Icons.directions_car,
    glyphColor: AppStatusColors.onColorFor(color),
    glyphSize: isMe ? 24 : 20,
    shadow: const BoxShadow(
      color: Color(0x59000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  );
  return MapMarker(
    id: 'colectivo_${colectivo.uid}',
    point: LatLng(colectivo.latitud, colectivo.longitud),
    icon: linea == null
        ? circulo
        : TaggedIcon(
            base: circulo,
            tag: linea.texto,
            tagColor: linea.color,
            tagTextColor: AppStatusColors.onColorFor(linea.color),
          ),
    // Sin señal se atenúa en vez de desaparecer: la unidad existe, pero su
    // posición puede estar desfasada (túnel, cerro sin cobertura).
    opacity: offline ? 0.45 : 1,
    semanticLabel: l10n.colectivoSemanticLabel(
      formatPatente(colectivo.idVehiculo),
      offline ? l10n.colectivoNoSignal : estadoLabel(colectivo.estado, l10n),
    ),
    onTap: onTap,
  );
}
