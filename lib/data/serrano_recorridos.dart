import 'package:latlong2/latlong.dart';
import 'package:taxi1/models/recorrido.dart';

/// Recorridos y cartolas de referencia oficial de Transportes Serrano (Quilpué).
///
/// Permite que la aplicación funcione de inmediato fuera de línea (offline-first)
/// con las 3 variantes reales de la garita y sus cartolas oficiales del MTT,
/// sin requerir sincronización previa con Firestore.
final List<Recorrido> kSerranoRecorridosSeed = [
  // --- VARIANTE BELLOTO 2000 ------------------------------------------------
  Recorrido(
    id: 'serrano-102-belloto2000',
    garitaId: 'garita-serrano',
    nombre: 'Línea 102: Belloto 2000 - Centro',
    varianteId: 'belloto-2000',
    varianteNombre: 'Belloto 2000',
    colorValue: 0xFF4A3F9E, // Índigo
    callesIda: const [
      'Estación Quilpué',
      'Plaza de Armas Quilpué',
      'Av. Los Carrera',
      'Av. Ramón Freire',
      'Marga Marga',
      'Baden Powell',
      'Ramón Ángel Jara',
      'Terminal Belloto 2000',
    ],
    callesVuelta: const [
      'Terminal Belloto 2000',
      'Ramón Ángel Jara',
      'Baden Powell',
      'Marga Marga',
      'Av. Ramón Freire',
      'Blanco Encalada',
      'Estación Quilpué',
    ],
    trazado: const [
      LatLng(-33.0478, -71.4429), // Estación Quilpué
      LatLng(-33.0472, -71.4395), // Los Carrera
      LatLng(-33.0465, -71.4320), // Freire / Metro El Sol
      LatLng(-33.0458, -71.4230), // Freire El Belloto
      LatLng(-33.0480, -71.4200), // Conexión Marga Marga
      LatLng(-33.0560, -71.4175), // Marga Marga
      LatLng(-33.0640, -71.4140), // Baden Powell
      LatLng(-33.0715, -71.4095), // Belloto 2000
    ],
    trazadoVuelta: const [
      LatLng(-33.0715, -71.4095), // Belloto 2000
      LatLng(-33.0640, -71.4140), // Baden Powell
      LatLng(-33.0560, -71.4175), // Marga Marga
      LatLng(-33.0480, -71.4200), // Conexión Freire
      LatLng(-33.0458, -71.4230), // Freire El Belloto
      LatLng(-33.0468, -71.4350), // Blanco Encalada
      LatLng(-33.0478, -71.4429), // Estación Quilpué
    ],
    activo: true,
  ),

  Recorrido(
    id: 'serrano-103-belloto-valencia',
    garitaId: 'garita-serrano',
    nombre: 'Línea 103: Belloto 2000 - Valencia',
    varianteId: 'belloto-2000',
    varianteNombre: 'Belloto 2000',
    colorValue: 0xFF00727C, // Teal
    callesIda: const [
      'Terminal Belloto 2000',
      'Baden Powell',
      'Av. Ramón Freire',
      'Av. Los Carrera',
      'Zenteno',
      'Sector Valencia',
    ],
    callesVuelta: const [
      'Sector Valencia',
      'Av. Los Carrera',
      'Thompson',
      'Av. Ramón Freire',
      'Baden Powell',
      'Terminal Belloto 2000',
    ],
    trazado: const [
      LatLng(-33.0715, -71.4095), // Belloto 2000
      LatLng(-33.0640, -71.4140), // Baden Powell
      LatLng(-33.0458, -71.4230), // Freire
      LatLng(-33.0472, -71.4400), // Los Carrera
      LatLng(-33.0440, -71.4550), // Zenteno
      LatLng(-33.0410, -71.4620), // Valencia
    ],
    trazadoVuelta: const [
      LatLng(-33.0410, -71.4620), // Valencia
      LatLng(-33.0440, -71.4550), // Zenteno
      LatLng(-33.0475, -71.4410), // Thompson
      LatLng(-33.0458, -71.4230), // Freire
      LatLng(-33.0640, -71.4140), // Baden Powell
      LatLng(-33.0715, -71.4095), // Belloto 2000
    ],
    activo: true,
  ),

  // --- VARIANTE LAS ROSAS ---------------------------------------------------
  Recorrido(
    id: 'serrano-105-las-rosas',
    garitaId: 'garita-serrano',
    nombre: 'Línea 105: Las Rosas - Hospital - Centro',
    varianteId: 'las-rosas',
    varianteNombre: 'Las Rosas',
    colorValue: 0xFF7B3FA0, // Violeta
    callesIda: const [
      'Sector Las Rosas',
      'Av. San Martín',
      'Hospital de Quilpué',
      'Av. Los Carrera',
      'Plaza de Armas',
      'Claudio Vicuña',
    ],
    callesVuelta: const [
      'Centro Quilpué',
      'Blanco Encalada',
      'Av. Ramón Freire',
      'Hospital de Quilpué',
      'Av. San Martín',
      'Sector Las Rosas',
    ],
    trazado: const [
      LatLng(-33.0380, -71.4350), // Las Rosas Norte
      LatLng(-33.0420, -71.4370), // San Martín
      LatLng(-33.0445, -71.4410), // Hospital Quilpué
      LatLng(-33.0472, -71.4420), // Los Carrera
      LatLng(-33.0483, -71.4430), // Claudio Vicuña
    ],
    trazadoVuelta: const [
      LatLng(-33.0483, -71.4430), // Claudio Vicuña
      LatLng(-33.0470, -71.4400), // Blanco Encalada
      LatLng(-33.0445, -71.4410), // Hospital Quilpué
      LatLng(-33.0420, -71.4370), // San Martín
      LatLng(-33.0380, -71.4350), // Las Rosas
    ],
    activo: true,
  ),

  // --- VARIANTE EL MIRADOR / CUMMING ----------------------------------------
  Recorrido(
    id: 'serrano-101-mirador-cumming',
    garitaId: 'garita-serrano',
    nombre: 'Línea 101: El Mirador - Cumming - Centro',
    varianteId: 'mirador',
    varianteNombre: 'El Mirador / Cumming',
    colorValue: 0xFFB0338A, // Magenta
    callesIda: const [
      'Sector El Mirador',
      'Av. Cumming',
      'Av. Los Carrera',
      'Plaza de Quilpué',
      'Estación Quilpué',
    ],
    callesVuelta: const [
      'Estación Quilpué',
      'Blanco Encalada',
      'Av. Cumming',
      'Sector El Mirador',
    ],
    trazado: const [
      LatLng(-33.0580, -71.4500), // El Mirador Alto
      LatLng(-33.0530, -71.4460), // Cumming Sur
      LatLng(-33.0485, -71.4435), // Cumming Centro
      LatLng(-33.0478, -71.4429), // Estación Quilpué
    ],
    trazadoVuelta: const [
      LatLng(-33.0478, -71.4429), // Estación Quilpué
      LatLng(-33.0475, -71.4410), // Blanco Encalada
      LatLng(-33.0530, -71.4460), // Cumming
      LatLng(-33.0580, -71.4500), // El Mirador Alto
    ],
    activo: true,
  ),

  Recorrido(
    id: 'serrano-104-cumming-marga-marga',
    garitaId: 'garita-serrano',
    nombre: 'Línea 104: Cumming - Marga Marga',
    varianteId: 'mirador',
    varianteNombre: 'El Mirador / Cumming',
    colorValue: 0xFF5D4037, // Café
    callesIda: const [
      'Av. Cumming',
      'Thompson',
      'Av. Marga Marga',
      'Sector Los Pinos',
    ],
    callesVuelta: const [
      'Sector Los Pinos',
      'Av. Marga Marga',
      'Blanco Encalada',
      'Av. Cumming',
    ],
    trazado: const [
      LatLng(-33.0530, -71.4460), // Cumming
      LatLng(-33.0475, -71.4410), // Thompson
      LatLng(-33.0550, -71.4250), // Marga Marga
      LatLng(-33.0620, -71.4280), // Los Pinos
    ],
    trazadoVuelta: const [
      LatLng(-33.0620, -71.4280), // Los Pinos
      LatLng(-33.0550, -71.4250), // Marga Marga
      LatLng(-33.0470, -71.4400), // Blanco Encalada
      LatLng(-33.0530, -71.4460), // Cumming
    ],
    activo: true,
  ),
];
