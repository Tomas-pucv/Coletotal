# Actualización de Recorridos, Cartolas Oficiales y Variantes (Branch Proto)

## 1. Resumen de la Actualización
Esta actualización introduce una reestructuración fundamental en la arquitectura de **ColeTotal**, adaptando el sistema al funcionamiento operativo y regulatorio real de los **Taxis Colectivos Chilenos** (caso piloto: *Transportes Serrano*, Quilpué), en conformidad con el Decreto Supremo N° 212 del Ministerio de Transportes y Telecomunicaciones (MTT).

---

## 2. ¿Qué se agregó y por qué?

### 2.1 Sustitución del modelo de "Paraderos" por "Cartolas Oficiales"
* **Por qué:** 
  En las versiones preliminares, la aplicación modelaba las rutas bajo el paradigma de buses/micros urbanos o Metro, asumiendo la existencia de "paraderos fijos" con señalética obligatoria. En los taxis colectivos de Chile:
  1. **No existen paraderos fijos:** Los usuarios toman el vehículo a mano alzada en cualquier punto permitido de la vía pública y descienden donde lo soliciten al conductor.
  2. **Efecto negativo previo:** Mostrar chinchetas de paraderos en el mapa confundía a los usuarios, haciéndoles creer que debían caminar hacia esquinas arbitrarias.
* **Qué se agregó:**
  Se introdujo el concepto formal de **Cartola Oficial** (secuencia autorizada de calles de **Ida** y **Vuelta**), permitiendo consultar de manera intuitiva el listado completo y ordenado de vías transitadas por cada línea.

---

### 2.2 Modelado de Variantes Operativas de Garita
* **Por qué:**
  La garita de Transportes Serrano opera formalmente mediante variantes territoriales que cubren distintos sectores de Quilpué (Belloto 2000, Las Rosas, Cumming / El Mirador). Los choferes están adscritos a una variante base, pero el administrador de garita necesita la flexibilidad de reasignarlos cuando la demanda u obras viales lo requieran.
* **Qué se agregó:**
  * **Entidad `Variante`:** Categorización explícita por sectores territoriales (`belloto-2000`, `las-rosas`, `cumming-mirador`).
  * **Asignación en `AppUser`:** Campo `varianteId` para vincular a los conductores con su variante base.
  * **Administración en `ChoferesAdminScreen`:** Selector interactivo para reasignar choferes de variante en tiempo real.

---

### 2.3 Selección Dinámica de Línea y Sentido en el Conductor (`TurnoScreen`)
* **Por qué:**
  El chofer no sigue un recorrido estático bidireccional simultáneo; durante su jornada conmuta constantemente entre el trayecto de ida hacia el destino y el de vuelta a la garita o terminal.
* **Qué se agregó:**
  * Selector de línea contextualizado a la variante del conductor.
  * Switch de sentido de marcha (`Ida` $\leftrightarrow$ `Vuelta`) que actualiza la telemetría en tiempo real hacia los pasajeros y la garita.

---

### 2.4 Rediseño Integral de la Pestaña de Recorridos (`RoutesScreen`)
* **Por qué:**
  Facilitar que el pasajero encuentre rápidamente qué colectivo le sirve según su ubicación actual y hacia dónde se dirige.
* **Qué se agregó:**
  * Pestañas superiores organizadas por **Variante**.
  * Búsqueda en texto completo por nombre de línea o por **nombre de calle** que compone la cartola.
  * Indicadores de proximidad calculados matemáticamente respecto a la posición GPS del usuario ("Cerca de ti", distancia estimada).
  * Tarjetas expandibles para inspeccionar la cartola paso a paso (calle por calle) tanto de Ida como de Vuelta.

---

### 2.5 Editor de Cartolas para Administradores de Garita (`RecorridosAdminScreen`)
* **Por qué:**
  Permitir a los operadores de garita ajustar los recorridos cuando cambian las autorizaciones del MTT, existen desvíos programados o se agregan nuevas calles.
* **Qué se agregó:**
  * Interfaz visual para creación y edición de líneas de colectivo.
  * Listas interactivas reordenables (`ReorderableListView`) para arrastrar y jerarquizar calles en las cartolas de Ida y Vuelta.
  * Catálogo de sugerencias automáticas de vías de Quilpué y selector cromático de color identificador de línea.

---

### 2.6 Proyección Geodésica Eficiente (`lib/utils/polyline.dart`)
* **Por qué:**
  Determinar si un colectivo o recorrido pasa cerca del usuario sin depender de APIs de ruteo externas lentas o con costo.
* **Qué se agregó:**
  * Algoritmo de proyección ortogonal punto-a-segmento sobre esferoide local ($\mathcal{O}(N)$), calculando con alta precisión la distancia mínima del usuario al eje de la traza.

---

### 2.7 Soporte Offline-First con Datos Semilla (`lib/data/serrano_recorridos.dart`)
* **Por qué:**
  Asegurar que la aplicación funcione de manera inmediata en zonas con baja cobertura o antes de que el dispositivo sincronice con Firestore.
* **Qué se agregó:**
  * Semilla oficial con las 3 variantes y las líneas reales de Transportes Serrano preconfiguradas en el código base.

---

## 3. Estado de la Aplicación y Observación sobre el Mapa

> [!WARNING]
> ### Observación Importante sobre las Líneas en el Mapa
> **Actualmente NO se muestran las líneas gráficas del recorrido dentro del mapa interactivo (`MapScreen`).**
> 
> * **Causa:** Al migrar el núcleo del sistema al modelo de cartolas oficiales (listados estructurados de calles), la renderización de polilíneas continuas en la capa `MapLine` requiere georreferenciar de extremo a extremo las coordenadas exactas de cada segmento vial o invocar el motor de enrutamiento (OSRM/Valhalla) para reconstruir la polilínea vectorial continua de cada sentido.
> * **Comportamiento del resto del sistema:** **Todo lo demás funciona correctamente.**
>   - El mapa base offline (PMTiles) carga y responde de forma fluida.
>   - La geolocalización del usuario y el seguimiento GPS operan sin problemas.
>   - La telemetría en tiempo real de los vehículos (marcadores dinámicos con nivel de ocupación y orientación) se actualiza de manera continua.
>   - La navegación y consulta de cartolas en la pestaña de Recorridos es 100% operativa.
>   - La gestión de turnos para choferes (iniciar turno, cambiar sentido Ida/Vuelta, reportar pasajeros) está validada y probada.
>   - El panel de administración de garita (gestión de choferes y edición de recorridos) funciona con persistencia en Firestore.
>   - Todos los 207 tests unitarios y de widgets del proyecto pasan con éxito (`flutter test`), y el analizador de código no reporta errores (`flutter analyze`).

---

## 4. Estructura de Archivos Modificados y Creados

```
docs/
├── ARQUITECTURA_Y_DISENO_TECNICO_RECORRIDOS.md  [Documento formal de diseño y diagramas UML/Mermaid]
└── ACTUALIZACION_PROTO_RECORRIDOS_Y_CARTOLAS.md [Este documento]

lib/
├── data/
│   └── serrano_recorridos.dart                  [Semilla offline de recorridos oficiales de Quilpué]
├── models/
│   ├── app_user.dart                            [Soporte para variante asignada a choferes]
│   ├── recorrido.dart                           [Cartolas ida/vuelta, variantes y algoritmos de distancia]
│   └── variante.dart                            [Modelo canónico de variante operacional]
├── screens/
│   ├── admin/
│   │   ├── choferes_admin_screen.dart           [Asignación de variantes operativas a choferes]
│   │   ├── garita_hub_screen.dart               [Acceso centralizado al módulo de recorridos y choferes]
│   │   ├── paraderos_admin_screen.dart          [Ajustes de transición]
│   │   └── recorridos_admin_screen.dart         [Editor de cartolas con ReorderableListView]
│   ├── driver/
│   │   └── turno_screen.dart                    [Control de turno: selección de variante y switch Ida/Vuelta]
│   ├── map_screen.dart                          [Actualización de capa cartográfica y remoción de paraderos]
│   └── routes_screen.dart                       [Nueva interfaz de usuario para consulta de cartolas]
├── services/
│   ├── garita_service.dart                      [Operaciones Firestore para recorridos y variantes]
│   ├── recorridos_service.dart                  [Gestión en memoria y sincronización reactiva de líneas]
│   └── turno_service.dart                       [Publicación de telemetría con variante y sentido]
└── utils/
    └── polyline.dart                            [Proyección geodésica ortogonal punto-a-segmento]

test/
└── recorridos_variantes_test.dart               [Suite de pruebas unitarias para cartolas y distancias]

firestore.rules                                  [Reglas de seguridad para variantes y recorridos]
```
