import 'package:latlong2/latlong.dart';
import 'package:taxi1/models/place_result.dart';

/// Catálogo de Puntos de Interés (POIs) estratégicos de la comuna de Quilpué.
///
/// Permite búsqueda instantánea (0 ms, sin red ni datos móviles) para
/// supermercados, plazas, centros de salud, colegios y estaciones de metro/tren.
/// Las calles van aparte, en el índice offline de `StreetIndex`.
const List<PlaceResult> kQuilpuePois = [
  // Supermercados y Centros Comerciales
  PlaceResult(
    id: 'poi_lider_belloto',
    name: 'Supermercado Líder Belloto',
    address: 'Av. Ramón Freire 2414, El Belloto, Quilpué',
    location: LatLng(-33.0456, -71.4162),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_portal_belloto',
    name: 'Portal Belloto (Jumbo / Easy / París)',
    address: 'Av. Ramón Freire 2414, El Belloto, Quilpué',
    location: LatLng(-33.0450, -71.4170),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_santa_isabel_centro',
    name: 'Santa Isabel Quilpué Centro',
    address: 'Claudio Vicuña 556, Quilpué',
    location: LatLng(-33.0483, -71.4429),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_santa_isabel_belloto',
    name: 'Santa Isabel El Belloto',
    address: 'Av. Ramón Freire 1351, El Belloto, Quilpué',
    location: LatLng(-33.0465, -71.4320),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_unimarc_blanco',
    name: 'Supermercado Unimarc',
    address: 'Blanco Encalada 1540, Quilpué',
    location: LatLng(-33.0478, -71.4402),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_mall_paseo_quilpue',
    name: 'Mall Paseo Quilpué',
    address: 'Avenida Los Carrera 601, Quilpué',
    location: LatLng(-33.0472, -71.4435),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_feria_belloto',
    name: 'Feria Municipal El Belloto',
    address: 'Av. Ramón Freire / Gómez Carreño, El Belloto',
    location: LatLng(-33.0461, -71.4235),
    isPoi: true,
  ),

  // Plazas y Espacios Cívicos
  PlaceResult(
    id: 'poi_plaza_armas',
    name: 'Plaza de Armas (Plaza Manuel Balmaceda)',
    address: 'Centro Cívico, Quilpué',
    location: LatLng(-33.0489, -71.4438),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_plaza_vieja',
    name: 'Plaza Vieja (Plaza Irarrázabal)',
    address: 'Irarrázabal / Thompson, Quilpué',
    location: LatLng(-33.0505, -71.4502),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_plaza_rengifo',
    name: 'Plaza Eugenio Rengifo',
    address: 'Vicuña Mackenna, Quilpué',
    location: LatLng(-33.0470, -71.4420),
    isPoi: true,
  ),

  // Salud y Hospitales
  PlaceResult(
    id: 'poi_hospital_quilpue',
    name: 'Hospital de Quilpué',
    address: 'San Martín 1270, Quilpué',
    location: LatLng(-33.0416, -71.4398),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_hospital_marga_marga',
    name: 'Nuevo Hospital Provincial Marga Marga',
    address: 'Av. Marga Marga, Quilpué',
    location: LatLng(-33.0575, -71.4485),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_cesfam_aviador_acevedo',
    name: 'CESFAM Aviador Acevedo',
    address: 'Aviador Acevedo 452, Quilpué',
    location: LatLng(-33.0435, -71.4460),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_consultorio_pompeya',
    name: 'CESFAM Pompeya Sur',
    address: 'Las Américas / Humboldt, Pompeya, Quilpué',
    location: LatLng(-33.0538, -71.4682),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_cesfam_belloto_sur',
    name: 'CESFAM Belloto Sur',
    address: 'Avenida El Belloto, Quilpué',
    location: LatLng(-33.0560, -71.4210),
    isPoi: true,
  ),

  // Educación y Universidades
  PlaceResult(
    id: 'poi_colegio_aconcagua',
    name: 'Colegio Aconcagua',
    address: 'Paso Hondo, Quilpué',
    location: LatLng(-33.0468, -71.4680),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_liceo_gronemeyer',
    name: 'Liceo Artístico Guillermo Gronemeyer',
    address: 'David Cortés 1015, Quilpué',
    location: LatLng(-33.0465, -71.4455),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_colegio_los_reyes',
    name: 'Colegio Los Reyes',
    address: 'El Belloto, Quilpué',
    location: LatLng(-33.0542, -71.4250),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_duoc_uc',
    name: 'Sede Formación / CFT Duoc UC Quilpué',
    address: 'Avenida Los Carrera, Quilpué',
    location: LatLng(-33.0479, -71.4410),
    isPoi: true,
  ),

  // Estaciones de Tren EFE y Terminales
  PlaceResult(
    id: 'poi_estacion_quilpue',
    name: 'Estación Metro/Tren Quilpué',
    address: 'Avenida Irarrázabal, Quilpué',
    location: LatLng(-33.0450, -71.4435),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_estacion_el_sol',
    name: 'Estación Metro/Tren El Sol',
    address: 'Avenida Baquedano, Quilpué',
    location: LatLng(-33.0458, -71.4312),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_estacion_belloto',
    name: 'Estación Metro/Tren Belloto',
    address: 'Avenida Gómez Carreño, El Belloto',
    location: LatLng(-33.0462, -71.4195),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_garita_serrano_cumming',
    name: 'Garita Transportes Serrano (Cumming)',
    address: 'Ricardo Cumming 100, Quilpué',
    location: LatLng(-33.0498, -71.4445),
    isPoi: true,
  ),

  // Instituciones Públicas
  PlaceResult(
    id: 'poi_municipalidad_quilpue',
    name: 'Municipalidad de Quilpué',
    address: 'Vicuña Mackenna 684, Quilpué',
    location: LatLng(-33.0488, -71.4420),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_registro_civil',
    name: 'Registro Civil e Identificación Quilpué',
    address: 'San Martín 650, Quilpué',
    location: LatLng(-33.0475, -71.4440),
    isPoi: true,
  ),
  PlaceResult(
    id: 'poi_comisaria_quilpue',
    name: 'Segunda Comisaría de Carabineros Quilpué',
    address: 'Avenida Los Carrera 450, Quilpué',
    location: LatLng(-33.0470, -71.4465),
    isPoi: true,
  ),
];
