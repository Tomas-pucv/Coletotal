# Arquitectura y Diseño Técnico: Recorridos, Cartolas y Variantes en ColeTotal
## Reconstrucción Formal del Proceso de Diseño Omitido en el Desarrollo Asistido por Agentes

---

### Resumen Ejecutivo y Motivación

En el desarrollo tradicional de software, el proceso previo a la codificación involucra semanas de levantamiento de requerimientos, diseño conceptual, especificación de modelos relacionales, diagramas de secuencia UML y formalización matemática de algoritmos. Cuando se emplean agentes autónomos y asistentes de inteligencia artificial, este proceso de ingeniería suele ocurrir de forma tácita en el espacio de razonamiento interno del modelo, traduciéndose de inmediato en código funcional sin dejar rastro documental formal.

Este documento tiene como propósito **recuperar y formalizar explícitamente todo el diseño de ingeniería** detrás de la transición de ColeTotal desde un modelo estándar de paraderos urbanos (tipo buses/micros) hacia el modelo operacional real de **Taxis Colectivos Chilenos** en la comuna de Quilpué (Transportes Serrano).

---

## 1. Justificación del Dominio de Negocio: La Realidad Operativa del Colectivo

### 1.1 La Discrepancia del Paradigma de "Paraderos"
En el transporte público mayor (buses urbanos, Metro, Transantiago/Red), el abordaje de pasajeros está restringido a infraestructura física segregada: **paraderos con señalética oficial y demarcación vial**. Bajo ese modelo, el ruteo de usuarios se modela como un grafo dirigido donde los vértices son paraderos estáticos $S = \{s_1, s_2, \dots, s_n\}$ y las aristas son los tramos entre ellos.

Sin embargo, en el transporte público menor chileno (**taxis colectivos**, regulados por el Decreto Supremo N° 212 del Ministerio de Transportes y Telecomunicaciones):
1. **No existen paraderos fijos:** Los pasajeros hacen parar al vehículo a mano alzada en cualquier punto de la vía pública donde esté permitido detenerse, y descienden donde lo soliciten al conductor.
2. **Visualizar paraderos en el mapa es perjudicial:** Confunde al usuario haciéndole creer que debe caminar obligatoriamente a una esquina lejana con un letrero que no existe en el terreno.

### 1.2 La Cartola Oficial como Estructura Canónica
El Ministerio de Transportes y Telecomunicaciones (MTT) formaliza la operación de una línea de colectivos a través de **Cartolas Oficiales**. Una cartola define la secuencia obligatoria de vías públicas por donde el colectivo tiene permiso de transitar:
* **Cartola de Ida:** Secuencia ordenada de calles y avenidas desde el terminal de origen hasta el punto de retorno.
* **Cartola de Vuelta:** Secuencia ordenada de calles y avenidas en sentido inverso de regreso a la garita.

### 1.3 El Concepto de Variantes y Operación de Garita
En la garita de **Transportes Serrano** (Quilpué), la línea se organiza operativamente en **tres variantes territoriales principales**:
1. **Belloto 2000:** Atiende el sector residencial de El Belloto 2000, Freire, Av. Valparaíso y Valencia.
2. **Las Rosas:** Recorre la zona de Las Rosas, Hospital de Quilpué, Los Carrera y centros de salud.
3. **El Mirador / Cumming:** Conecta Cumming, El Mirador y el centro neurálgico comercial de Quilpué.

**Regla de negocio de asignación:** Cada chofer tiene asignada una **variante base** a la que pertenece habitualmente su vehículo. No obstante, para responder a horas punta, cortes de tránsito o eventos imprevistos, **el administrador de la garita puede autorizar su reasignación temporal o permanente a otra variante**. En su jornada diaria, el chofer selecciona la línea específica y conmuta dinámicamente el sentido de marcha (**Ida** o **Vuelta**).

---

## 2. Diagramas de Diseño Formal

### 2.1 Modelo Conceptual de Dominio (Diagrama de Clases)

El siguiente diagrama detalla las entidades de datos, cardinalidades y métodos del nuevo modelo de garita:

```mermaid
classDiagram
    direction TB

    class Garita {
        +String id
        +String nombre
        +String direccion
        +String telefono
        +LatLng ubicacion
    }

    class Variante {
        +String id
        +String nombre
        +String descripcion
    }

    class Recorrido {
        +String id
        +String garitaId
        +String nombre
        +String varianteId
        +String varianteNombre
        +List~String~ callesIda
        +List~String~ callesVuelta
        +int colorValue
        +String? geometria
        +String? geometriaVuelta
        +List~LatLng~ trazado
        +List~LatLng~ trazadoVuelta
        +bool activo
        +distanceFrom(LatLng point) double
        +matchesQuery(String query) bool
        +todasLasCalles List~String~
    }

    class AppUser {
        +String uid
        +String email
        +String nombre
        +String patente
        +String garitaId
        +String? varianteId
        +UserRole rol
        +bool activo
    }

    class Turno {
        +String uidChofer
        +String patente
        +String garitaId
        +String recorridoId
        +String? varianteId
        +bool sentidoIda
        +ColectivoEstado estado
        +bool enServicio
        +iniciarTurno()
        +setSentidoIda(bool ida)
        +setEstado(ColectivoEstado)
        +terminarTurno()
    }

    class TelemetriaPayload {
        +String uid
        +String idVehiculo
        +double latitud
        +double longitud
        +ColectivoEstado estado
        +String garitaId
        +String recorridoId
        +String? varianteId
        +bool sentidoIda
        +int timestamp
        +bool conectado
    }

    Garita "1" *-- "3" Variante : agrupa
    Variante "1" *-- "1..*" Recorrido : contiene
    Garita "1" o-- "1..*" AppUser : registra
    AppUser "1" --> "0..1" Variante : tiene asignada
    AppUser "1" --> "1" Turno : opera
    Turno "1" --> "1" Recorrido : ejecuta
    Turno ..> TelemetriaPayload : transmite cada 3s
```

---

### 2.2 Arquitectura del Sistema y Persistencia Offline-First

ColeTotal fue rediseñado bajo un esquema **Offline-First**, asegurando que los usuarios en zonas de cerros o con baja cobertura celular en Quilpué (como Baden Powell alto, Cumming o Marga Marga rural) continúen operando sin bloqueos:

```mermaid
flowchart TD
    subgraph UI ["Capa de Presentación (Flutter UI)"]
        Mapa["MapScreen (Sin paraderos)"]
        Recorridos["RoutesScreen (Recorridos y Cartolas)"]
        Turno["TurnoScreen (Chofer: Variante y Sentido)"]
        AdminRec["RecorridosAdminScreen (Editor de Cartolas)"]
        AdminChof["ChoferesAdminScreen (Gestión de Variantes)"]
        Flota["FlotaScreen (Supervisión de Flota)"]
    end

    subgraph Logic ["Capa de Lógica y Servicios (Singleton State)"]
        RecService["RecorridosService (Cálculo de cercanía)"]
        TurnoService["TurnoService (Gestor de Jornada)"]
        GaritaService["GaritaService (Administración)"]
        TelemetriaService["FirebaseTelemetriaService"]
        LocService["LocationService (Foreground Service)"]
    end

    subgraph Data ["Capa de Datos y Red (Híbrida Offline-First)"]
        Firestore["Cloud Firestore (Recorridos, Usuarios, Garitas)"]
        RTDB["Realtime Database (colectivos_activos)"]
        SeedLocal["Semilla Local (serrano_recorridos.dart)"]
        TileCache["Caché de Teselas Vectoriales (CARTO / MapTiler)"]
    end

    UI --> Logic
    Logic --> Data
    SeedLocal -.->|Carga inmediata offline| RecService
    Firestore -->|Sincronización online| GaritaService
    RTDB <-->|Stream 3s en vivo| TelemetriaService
```

---

### 2.3 Algoritmo Matemático: Proyección Ortogonal a la Polilínea Vial

Para calcular cuál línea de colectivos se encuentra más próxima al usuario, no se pueden usar distancias centroide o euclidianas simples a un punto fijo. El cálculo requiere encontrar la **distancia ortogonal mínima desde el punto del usuario $P$ hacia cualquier segmento de la polilínea del recorrido**.

#### Formulación Matemática
Sea la polilínea del recorrido compuesta por vértices geográficos consecutivos:
$$\mathcal{L} = \{V_1, V_2, \dots, V_N\}, \quad V_i = (\text{lat}_i, \text{lon}_i)$$

Para cada segmento definido por los puntos extremos $A = V_i$ y $B = V_{i+1}$:
1. Se define el vector del segmento: $\vec{v} = B - A$
2. Se define el vector desde $A$ hasta el punto del usuario $P$: $\vec{w} = P - A$
3. La proyección escalar de $P$ sobre la recta que contiene a $AB$ se obtiene mediante el producto punto normalizado:
$$t = \frac{\vec{w} \cdot \vec{v}}{\|\vec{v}\|^2} = \frac{(P_x - A_x)(B_x - A_x) + (P_y - A_y)(B_y - A_y)}{(B_x - A_x)^2 + (B_y - A_y)^2}$$

4. Para limitar la proyección al **segmento cerrado** $[A, B]$, el parámetro $t$ se acota al intervalo $[0, 1]$:
$$t^* = \max(0, \min(1, t))$$

5. El punto más cercano $Q$ sobre el segmento vial es:
$$Q = A + t^* \cdot \vec{v}$$

6. La distancia geodésica exacta en metros se calcula aplicando la fórmula de Haversine:
$$d(P, Q) = 2 R \arcsin \left( \sqrt{\sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_P) \cos(\phi_Q) \sin^2\left(\frac{\Delta \lambda}{2}\right)} \right)$$
Donde $R = 6.371.000\text{ m}$, $\phi = \text{latitud}$ y $\lambda = \text{longitud}$.

7. La distancia del usuario a la línea completa corresponde al ínfimo de todos los segmentos:
$$D_{\text{recorrido}}(P) = \min_{i = 1 \dots N-1} d(P, Q_i)$$

```mermaid
flowchart LR
    P["Posición Pasajero (P)"]
    A["Vértice Vial A"]
    B["Vértice Vial B"]
    Q["Punto Proyectado (Q)"]

    A --- Q --- B
    P -.->|"d(P, Q) = Distancia Mínima"| Q
```

---

### 2.4 Diagrama de Secuencia: Consulta y Búsqueda por Cartola

El siguiente diagrama detalla cómo un pasajero consulta las líneas ordenadas por cercanía y busca una calle específica dentro de las cartolas oficiales:

```mermaid
sequenceDiagram
    autonumber
    actor Pasajero
    participant UI as RoutesScreen
    participant RS as RecorridosService
    participant Poly as PolylineUtils
    participant Model as Recorrido

    Pasajero->>UI: Abre pestaña "Recorridos"
    UI->>RS: filtrar(userLocation, query, varianteId)
    loop Para cada Recorrido en catálogo
        RS->>Model: distanceFrom(userLocation)
        Model->>Poly: distanceToPolyline(userLocation, trazado)
        Poly-->>Model: distanciaIda (metros)
        Model->>Poly: distanceToPolyline(userLocation, trazadoVuelta)
        Poly-->>Model: distanciaVuelta (metros)
        Model-->>RS: min(distanciaIda, distanciaVuelta)
    end
    RS->>RS: sort((a, b) => distA.compareTo(distB))
    RS-->>UI: Lista de líneas ordenadas (más cercana primero)
    UI-->>Pasajero: Muestra tarjetas con distancia y botón "Línea más cercana"

    Pasajero->>UI: Escribe "Baden Powell" en el buscador
    UI->>RS: filtrar(query: "Baden Powell")
    loop Para cada Recorrido
        RS->>Model: matchesQuery("Baden Powell")
        Note over Model: Compara contra nombre, varianteNombre y todasLasCalles (Ida y Vuelta)
        Model-->>RS: true / false
    end
    RS-->>UI: Líneas filtradas que circulan por Baden Powell
    UI-->>Pasajero: Visualiza líneas 101 y 104 con sus cartolas
```

---

### 2.5 Diagrama de Secuencia: Ciclo de Vida del Turno del Chofer y Telemetría

Describe cómo opera el conductor en su jornada, cómo se valida su variante asignada y cómo se sincroniza el sentido de marcha en tiempo real:

```mermaid
sequenceDiagram
    autonumber
    actor Chofer
    participant App as TurnoScreen
    participant TS as TurnoService
    participant LS as LocationService
    participant RTDB as Firebase Realtime Database
    participant FS as Firestore (Auditoría)
    participant Pasajeros as Mapa Pasajeros

    Chofer->>App: Ingresa a pestaña "Turno"
    App->>TS: init() (Lee perfil y varianteId asignada)
    App-->>Chofer: Muestra variante (ej. "Belloto 2000") y selector de sentido (Ida)
    Chofer->>App: Selecciona Línea 101 y pulsa "Iniciar Turno"
    App->>TS: iniciarTurno()
    TS->>LS: enableDriverTracking(true)
    Note over LS: Inicia Android Foreground Service persistente con WakeLock
    loop Cada 3 segundos (Transmisión continua)
        LS->>TS: onLocationChanged(lat, lng)
        TS->>RTDB: set(colectivos_activos/{uid}) [lat, lng, patente, sentidoIda=true, estado]
        RTDB-->>Pasajeros: Actualiza marcador en vivo con sentido "Ida"
    end

    Note over Chofer: Completa recorrido de ida y llega a terminal
    Chofer->>App: Conmuta sentido de marcha a "Vuelta"
    App->>TS: setSentidoIda(false)
    TS->>RTDB: update(colectivos_activos/{uid}, {sentidoIda: false})
    RTDB-->>Pasajeros: Actualiza marcador y trazado a "Vuelta"

    Chofer->>App: Pulsa "Terminar Turno"
    App->>TS: terminarTurno()
    TS->>LS: enableDriverTracking(false)
    TS->>RTDB: remove(colectivos_activos/{uid})
    TS->>FS: set(garitas/{gid}/auditoria_turnos/{id}, {duracion, distancia, sentidoFin})
    RTDB-->>Pasajeros: Remueve vehículo del mapa
```

---

### 2.6 Máquina de Estados del Colectivo en Tiempo Real

El vehículo en servicio transita a través de estados operacionales y estados de conectividad:

```mermaid
stateDiagram-v2
    [*] --> FueraDeServicio: Aplicación iniciada

    state "En Servicio (Transmitiendo)" as EnServicio {
        [*] --> Disponible: Inicia Turno
        Disponible --> MedioLleno: Chofer reporta 2-3 pasajeros
        MedioLleno --> Lleno: Chofer reporta 4 pasajeros
        Lleno --> MedioLleno: Baja pasajero
        MedioLleno --> Disponible: Colectivo desocupado
    }

    FueraDeServicio --> EnServicio: Chofer pulsa Iniciar Turno

    state "Monitoreo de Red (Clientes)" as Red {
        Online: Conectado (Opacidad 100%)
        SinSenal: Sin Señal (Opacidad 45% tras 45s)
        Obsoleto: Purgado de Memoria (tras 180s)

        Online --> SinSenal: seemsOffline() == true
        SinSenal --> Online: Llega nueva coordenada GPS
        SinSenal --> Obsoleto: vigentes() elimina nodo
    }

    EnServicio --> FueraDeServicio: Chofer pulsa Terminar Turno o Garita suspende cuenta
    EnServicio --> Red: Publica telemetría
```

---

### 2.7 Flujo de Administración: Modelado de Recorridos por Cartolas

El nuevo editor de recorridos (`RecorridoEditorScreen`) permite a la garita modelar y adaptar sus líneas de manera visual y estructurada:

```mermaid
flowchart TD
    Inicio([Admin abre RecorridosAdminScreen]) --> Lista[Visualiza líneas con chip de variante y conteo de calles]
    Lista --> Accion{Acción del Admin}
    Accion -->|Editar| Editor[Abre RecorridoEditorScreen]
    Accion -->|Crear| Editor

    subgraph TabEditor ["Editor Modular de Cartolas"]
        Pestana1["Pestaña 1: General<br>• Nombre de línea<br>• Selector de Variante Operacional<br>• Selector cromático de color<br>• Switch Activo"]
        Pestana2["Pestaña 2: Cartola de Ida<br>• ReorderableListView de calles<br>• Agregar calle con sugerencias de Quilpué<br>• Reordenar tramos arrastrando filas<br>• Eliminar calle"]
        Pestana3["Pestaña 3: Cartola de Vuelta<br>• ReorderableListView de retorno<br>• Secuencia de calles de regreso"]
    end

    Editor --> TabEditor
    TabEditor --> Validar{¿Tiene nombre y calles en cartola?}
    Validar -->|No| Alerta[Muestra SnackBar explicativo y enfoca pestaña faltante]
    Validar -->|Sí| Guardar[Invoca GaritaService.upsertRecorrido]
    Guardar --> Firestore[(Firestore: coleccion recorridos)]
    Firestore --> Sync[Sincronización en vivo con Choferes y Pasajeros]
    Sync --> Fin([Fin de la operación])
```

---

## 3. Matriz de Trazabilidad entre Requerimientos y Casos de Prueba

| Requerimiento del Sistema | Módulo Implementado | Caso de Prueba Formal (Word/Plan) | Estado |
| :--- | :--- | :--- | :--- |
| **RF-01: Mapa Interactivo sin Paraderos** | `lib/screens/map_screen.dart` | **P01** | Implementado & Verificado |
| **RF-02: Seguimiento GPS Continuo** | `lib/services/location_service.dart` | **P02** | Implementado & Verificado |
| **RF-03: Pestaña Recorridos y Proximidad** | `lib/screens/routes_screen.dart` | **P03** | Implementado & Verificado |
| **RF-04: Consulta de Cartola Oficial** | `lib/screens/routes_screen.dart` | **P04** | Implementado & Verificado |
| **RF-05: Proyección Ortogonal a Traza** | `lib/utils/polyline.dart` | **P05** | Implementado & Verificado |
| **RF-06: Turno Chofer, Variante y Sentido** | `lib/screens/driver/turno_screen.dart` | **P06** | Implementado & Verificado |
| **RF-07: Semaforización de Capacidad** | `lib/services/turno_service.dart` | **P07** | Implementado & Verificado |
| **RF-08: Monitoreo de Sentido de Marcha** | `lib/screens/map_screen.dart` | **P08** | Implementado & Verificado |
| **RF-09: Consola de Supervisión de Flota** | `lib/screens/admin/flota_screen.dart` | **P09** | Implementado & Verificado |
| **RF-10: Administración de Variantes** | `lib/screens/admin/choferes_admin_screen.dart` | **P10** | Implementado & Verificado |
| **RF-11: Editor de Cartolas de Garita** | `lib/screens/admin/recorridos_admin_screen.dart` | **P11** | Implementado & Verificado |
| **RF-12: Suspensión Inmediata de Chofer** | `lib/services/garita_service.dart` | **P12** | Implementado & Verificado |
| **RF-13: Enrolamiento por Código Secreto** | `lib/screens/auth/register_screen.dart` | **P13** | Implementado & Verificado |
| **RF-14: Operación Offline Resiliente** | `lib/data/serrano_recorridos.dart` | **P14** | Implementado & Verificado |
| **RF-15: Interfaz Responsiva Móvil/Tablet** | `lib/screens/main_screen.dart` | **P15** | Implementado & Verificado |
| **RF-16: Navegación Cartográfica Fluida** | `lib/widgets/app_map.dart` | **P16** | Implementado & Verificado |
| **RNF-06: Supresión de Colectivos Fantasma**| `lib/models/colectivo_activo.dart` | **P17** | Implementado & Verificado |
| **Operacional: Actualización OTA Segura** | `lib/services/app_update_service.dart` | **P18** | Implementado & Verificado |

---

## 4. Conclusiones para la Defensa de Título

1. **Alineación con el Territorio:** Al suprimir los paraderos y adoptar cartolas oficiales y variantes, ColeTotal deja de ser una copia de aplicaciones metropolitanas genéricas y se convierte en una herramienta **fiel al modelo regulatorio y operativo real de los taxis colectivos chilenos**.
2. **Eficiencia y Precisión Computacional:** El uso de proyecciones ortogonales geodésicas escalares ($\mathcal{O}(N)$ por trazado) garantiza ordenamientos instantáneos en el dispositivo móvil sin depender de servidores de ruteo externos para calcular cercanía.
3. **Rigurosidad Metodológica:** Al explicitar y diagramar formalmente los modelos conceptuales, arquitecturas, máquinas de estados y secuencias de interacción, el proyecto subsana el vacío documental que suele generarse al utilizar agentes autónomos en la generación de código.
