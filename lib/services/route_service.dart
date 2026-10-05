import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/services/osrm_client.dart';

/// Velocidad a pie con la que se estima el tiempo cuando el único proveedor
/// que respondió calcula en auto: 1,3 m/s ≈ 4,7 km/h, un paso normal.
const double kWalkingSpeedMps = 1.3;

/// Resultado de un cálculo de ruta. Agrupa los puntos + métricas para que
/// la UI pueda mostrar distancia y duración sin parsear de nuevo.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;

  /// Tiempo **caminando**.
  final double durationSeconds;
  final String provider; // 'ORS' | 'OSRM'

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.provider,
  });

  // El formateo de distancia y duración vive en `utils/distance_format.dart`,
  // que además localiza las unidades. Tenerlo acá obligaba a que el servicio
  // conociera el idioma y duplicaba la lógica que ya existía en las pantallas.
}

/// Servicio de ruteo **a pie** hasta un paradero.
///
/// Antes pedía rutas en auto (`driving-car` en OpenRouteService, `driving` en
/// OSRM) y mostraba el tiempo en auto como si fuera caminando: un trayecto de
/// 640 m y nueve minutos a pie aparecía como 1,1 km y dos minutos, con rodeos
/// por el sentido de las calles que a un peatón no le importan.
///
/// Estrategia:
/// 1. Si hay API key de OpenRouteService (vía `--dart-define=ORS_API_KEY=...`
///    o guardada en SharedPreferences), ORS con perfil `foot-walking`.
/// 2. Si no, OSRM peatonal (servidor de FOSSGIS, sin key).
/// 3. Si tampoco, OSRM en auto, con el tiempo recalculado a paso de peatón.
/// 4. Si todo falla, devolver `false` y dejar que la UI muestre el error.
class RouteService extends ChangeNotifier {
  RouteService._internal();
  static final RouteService instance = RouteService._internal();

  LatLng? _origin;
  BusStop? _destination;
  List<LatLng> _routePoints = [];
  RouteResult? _routeInfo;
  bool _loadingRoute = false;
  String? _lastError;
  String? _activeProvider;

  /// Número de la petición en curso. Una respuesta que llega cuando ya se
  /// pidió otra ruta (o se cerró la actual) se descarta en vez de pisar a la
  /// vigente.
  int _request = 0;

  http.Client _client = http.Client();

  @visibleForTesting
  set debugClient(http.Client client) => _client = client;

  /// Desde dónde se calculó la ruta actual.
  LatLng? get origin => _origin;
  BusStop? get destination => _destination;
  List<LatLng> get routePoints => _routePoints;
  RouteResult? get routeInfo => _routeInfo;
  bool get loadingRoute => _loadingRoute;
  String? get lastError => _lastError;
  String? get activeProvider => _activeProvider;

  void setOrigin(LatLng origin) {
    // Filtrar coordenadas inválidas para que no se propaguen a la polilínea
    // ni a los marcadores (causa del error "LatLng is not finite").
    if (!OsrmClient.isValidLatLng(origin)) return;
    _origin = origin;
    notifyListeners();
  }

  void setDestination(BusStop destination) {
    // Otro paradero: la ruta anterior ya no aplica. Antes seguía dibujada, con
    // su distancia y su tiempo, bajo el nombre del paradero nuevo mientras se
    // calculaba la nueva.
    if (destination.id != _destination?.id) {
      _routePoints = [];
      _routeInfo = null;
      _activeProvider = null;
      _lastError = null;
    }
    _destination = destination;
    notifyListeners();
  }

  void clearDestination() {
    _request++;
    _destination = null;
    _routePoints = [];
    _routeInfo = null;
    _lastError = null;
    _activeProvider = null;
    _loadingRoute = false;
    notifyListeners();
  }

  /// Vuelve a resolver el destino contra la lista viva de paraderos.
  ///
  /// El destino se guarda **por valor**, así que si el administrador mueve o da
  /// de baja el paradero que el pasajero tiene seleccionado, la polilínea
  /// seguiría apuntando a un fantasma: al punto viejo, con el nombre viejo. Se
  /// llama desde `main()` cada vez que cambian los paraderos.
  void refreshDestination(BusStop? Function(String id) resolve) {
    final current = _destination;
    if (current == null) return;

    final fresh = resolve(current.id);
    if (fresh == null) {
      // El paradero ya no existe: mejor cerrar la ruta que dibujarla hacia un
      // lugar que la garita eliminó.
      clearDestination();
      return;
    }
    if (fresh.location == current.location && fresh.name == current.name) {
      return;
    }
    _destination = fresh;
    notifyListeners();
  }

  Future<String> _resolveApiKey() async {
    // 1) Compile-time (preferido): --dart-define=ORS_API_KEY=xxx
    const compileKey = String.fromEnvironment('ORS_API_KEY', defaultValue: '');
    if (compileKey.isNotEmpty) return compileKey;

    // 2) SharedPreferences (seteado programáticamente, sin UI).
    final sp = await SharedPreferences.getInstance();
    return sp.getString('ors_api_key') ?? '';
  }

  /// Calcula la ruta a pie entre [origin] y [dest]. Devuelve `true` si se
  /// obtuvo una polilínea válida, `false` en caso contrario.
  Future<bool> fetchRoute(LatLng origin, BusStop dest) async {
    final request = ++_request;

    // No llamar a las APIs si el origen o el destino son inválidos.
    if (!OsrmClient.isValidLatLng(origin) ||
        !OsrmClient.isValidLatLng(dest.location)) {
      _lastError = 'invalid_coords';
      _loadingRoute = false;
      _routePoints = [];
      _routeInfo = null;
      notifyListeners();
      return false;
    }

    // La ruta parte de donde el usuario está *ahora*.
    _origin = origin;
    _loadingRoute = true;
    _lastError = null;
    notifyListeners();

    RouteResult? result;
    var error = 'no_route';
    try {
      final apiKey = await _resolveApiKey();
      if (apiKey.isNotEmpty) {
        result = await _fetchFromORS(origin, dest, apiKey);
        // Si ORS falló, se cae a OSRM abajo (no se corta acá).
      }
      result ??= await _fetchFromOSRM(origin, dest);
      if (result == null) error = 'provider_error';
    } catch (e, st) {
      debugPrint('fetchRoute error: $e\n$st');
      error = 'generic_error';
    }

    // Mientras tanto se pidió otra ruta o se cerró esta: la respuesta sobra.
    if (request != _request) return false;

    _loadingRoute = false;
    if (result == null) {
      _lastError = error;
      _routePoints = [];
      _routeInfo = null;
      _activeProvider = null;
      notifyListeners();
      return false;
    }

    _routePoints = result.points;
    _routeInfo = result;
    _activeProvider = result.provider;
    _lastError = null;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // OpenRouteService
  // ---------------------------------------------------------------------------

  Future<RouteResult?> _fetchFromORS(
    LatLng origin,
    BusStop dest,
    String apiKey,
  ) async {
    try {
      final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/foot-walking/geojson',
      );
      final payload = json.encode({
        'coordinates': [
          [origin.longitude, origin.latitude],
          [dest.location.longitude, dest.location.latitude],
        ],
        'instructions': false,
      });

      final res = await _client
          .post(
            url,
            headers: {
              'Authorization': apiKey,
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        debugPrint('ORS ${res.statusCode}: ${res.body}');
        return null;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      // Tomar la primera alternativa (ORS ya devuelve la óptima por defecto).
      final feature = features.first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null || geometry['coordinates'] == null) return null;

      final coords = _parseGeoJsonCoordinates(
        geometry,
      ).where(OsrmClient.isValidLatLng).toList();
      if (coords.isEmpty) return null;

      // Métricas
      double dist = 0;
      double dur = 0;
      final props = feature['properties'] as Map<String, dynamic>?;
      final summary = props?['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        final d = summary['distance'];
        final t = summary['duration'];
        if (d is num) dist = d.toDouble();
        if (t is num) dur = t.toDouble();
      }

      return RouteResult(
        points: coords,
        distanceMeters: dist,
        durationSeconds: dur > 0 ? dur : dist / kWalkingSpeedMps,
        provider: 'ORS',
      );
    } catch (e) {
      debugPrint('ORS exception: $e');
      return null;
    }
  }

  List<LatLng> _parseGeoJsonCoordinates(Map<String, dynamic> geometry) {
    final coords = <LatLng>[];
    final dynamic coordsRaw = geometry['coordinates'];
    final geomType = (geometry['type'] as String?)?.toLowerCase() ?? '';

    try {
      if (geomType == 'linestring' && coordsRaw is List) {
        for (final c in coordsRaw) {
          if (c is List && c.length >= 2) {
            final lon = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            coords.add(LatLng(lat, lon));
          }
        }
      } else if (geomType == 'multilinestring' && coordsRaw is List) {
        for (final seg in coordsRaw) {
          if (seg is! List) continue;
          for (final c in seg) {
            if (c is List && c.length >= 2) {
              final lon = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              coords.add(LatLng(lat, lon));
            }
          }
        }
      }
    } catch (_) {
      return const [];
    }
    return coords;
  }

  // ---------------------------------------------------------------------------
  // OSRM (sin API key)
  // ---------------------------------------------------------------------------

  Future<RouteResult?> _fetchFromOSRM(LatLng origin, BusStop dest) async {
    final points = [origin, dest.location];

    final foot = await OsrmClient.route(points, profile: OsrmProfile.foot);
    if (foot != null) {
      return RouteResult(
        points: foot.points,
        distanceMeters: foot.distanceMeters,
        durationSeconds: foot.durationSeconds > 0
            ? foot.durationSeconds
            : foot.distanceMeters / kWalkingSpeedMps,
        provider: 'OSRM',
      );
    }

    // Último recurso: el servidor de demostración sólo calcula en auto. La
    // geometría sirve igual para orientarse, pero su tiempo es de auto, así
    // que se recalcula a paso de peatón.
    final car = await OsrmClient.route(points);
    if (car == null) return null;
    return RouteResult(
      points: car.points,
      distanceMeters: car.distanceMeters,
      durationSeconds: car.distanceMeters / kWalkingSpeedMps,
      provider: 'OSRM',
    );
  }
}
