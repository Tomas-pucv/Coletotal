/// Variante de operación de una garita de colectivos.
///
/// En el modelo de negocio de Transportes Serrano (Quilpué), las líneas se
/// agrupan en tres variantes principales:
/// - Belloto 2000
/// - Las Rosas
/// - El Mirador / Cumming
///
/// Cada chofer tiene asignada una variante base, pero un administrador puede
/// autorizar su reasignación a otra según la demanda operacional del día.
class Variante {
  const Variante({
    required this.id,
    required this.nombre,
    required this.descripcion,
  });

  final String id;
  final String nombre;
  final String descripcion;

  @override
  bool operator ==(Object other) => other is Variante && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Variante($id, $nombre)';
}

/// Catálogo oficial de variantes operacionales de Transportes Serrano.
const List<Variante> kVariantesSerrano = [
  Variante(
    id: 'belloto-2000',
    nombre: 'Belloto 2000',
    descripcion: 'Recorridos hacia El Belloto 2000, Freire y Valencia',
  ),
  Variante(
    id: 'las-rosas',
    nombre: 'Las Rosas',
    descripcion: 'Recorridos hacia Las Rosas, Hospital de Quilpué y Los Carrera',
  ),
  Variante(
    id: 'mirador',
    nombre: 'El Mirador / Cumming',
    descripcion: 'Recorridos hacia Cumming, El Mirador y Quilpué Centro',
  ),
];

Variante? varianteById(String? id) {
  if (id == null) return null;
  for (final v in kVariantesSerrano) {
    if (v.id == id) return v;
  }
  return null;
}
