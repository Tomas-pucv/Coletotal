# Sistema ColeTotal: Estrategia de Respaldo, Soberanía de Datos y Mitigación de Vendor Lock-in

**Proyecto de Título:** ColeTotal — Sistema de Información y Telemetría para Taxis Colectivos en Quilpué  
**Asignatura:** INF 4560-01 — Escuela de Ingeniería Informática | Pontificia Universidad Católica de Valparaíso  
**Autores:** Marco Fernandoy Rojas · Tomás Moraga Gálvez  
**Comisión Evaluadora:** Profesora Guía Sra. Claudia Vasconcellos · Profesor Correferente Sr. Francisco Ponce  
**Fecha:** Septiembre 2026  

---

## 1. Introducción y Justificación ante la Comisión

Durante la defensa de avance del proyecto de título, la comisión evaluadora formuló una observación de ingeniería fundamental sobre la arquitectura de persistencia:

> *"No se puede depender ciegamente de Firebase como único punto de fallo (Single Point of Failure - SPOF) ni quedar atado a un único proveedor propietario (Vendor Lock-in). ¿Qué ocurre si la plataforma sufre una interrupción de servicio, altera unilateralmente sus esquemas tarifarios o si la línea requiere soberanía física sobre su información?"*

El presente documento formaliza la respuesta de ingeniería de software a dicha observación, estructurando una **Estrategia de Respaldo Multi-Capa y Soberanía de Datos** diseñada específicamente para la realidad técnica y presupuestaria del transporte público menor en Quilpué.

---

## 2. Diferenciación de Naturalezas de Datos

Para diseñar un sistema de respaldo técnicamente riguroso, es mandatorio descomponer la base de datos en sus dos naturalezas operacionales:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ARQUITECTURA DE PERSISTENCIA                    │
├───────────────────────────────────┬────────────────────────────────────┤
│ 1. DATOS MAESTROS Y CONFIGURACIÓN │ 2. TELEMETRÍA EFÍMERA EN VIVO      │
│    (Cloud Firestore)              │    (Firebase Realtime Database)    │
│ • Paraderos y coordenadas GPS     │ • Posiciones GPS cada 3 segundos   │
│ • Trazados de 7 recorridos viales │ • Estado de capacidad (semáforo)   │
│ • Cuentas de chofer y garitas     │ • Socket TCP temporal (vida < 90s) │
│ • Frecuencia: Baja (escrituras)   │ • Frecuencia: Alta (streaming)     │
│ ► ESTRATEGIA: Volcados periódicos │ ► ESTRATEGIA: Historización al     │
│   a formatos abiertos (JSON/GeoJSON)│    cierre de turno y sifón local   │
└───────────────────────────────────┴────────────────────────────────────┘
```

---

## 3. Propuesta 1: Soberanía y Portabilidad de Datos Maestros (Firestore)

Los activos más valiosos del sistema son las coordenadas de los paraderos oficiales, la topología secuencial de los recorridos de la línea y el padrón de conductores.

### 3.1. Formatos Abiertos de Intercambio
Para garantizar la **portabilidad absoluta** y evitar formatos binarios cerrados, los respaldos se generan en dos estándares de la industria:
1. **JSON Canónico:** Para garitas, usuarios, roles y recorridos.
2. **GeoJSON Estándar (RFC 7946):** Para la red de paraderos georreferenciados. Este formato permite abrir los datos directamente en herramientas GIS de escritorio (QGIS, ArcGIS) o importarlos en motores espaciales como **PostgreSQL con extensión PostGIS**.

### 3.2. Herramienta Ejecutable de Respaldo Local (`backup_coletotal.js`)
Se implementó un script en Node.js que interactúa con la REST API de Google Cloud Firestore mediante tokens de administración, descargando de forma íntegra las colecciones a un directorio local con marca de tiempo:

```
backups/backup_2026-09-30T02-28-33/
├── manifest.json            # Metadatos del respaldo (fecha, proyecto, conteo)
├── garitas.json             # Metadatos de la terminal
├── codigos_acceso.json      # Códigos de enrolamiento autorizados
├── usuarios.json            # Padrón de choferes y administradores
├── paraderos.json           # Lista de paraderos en JSON
├── paraderos.geojson        # Puntos vectoriales espaciales RFC 7946
├── recorridos.json          # Las 7 líneas con sus paraderos ordenados
└── colectivos_activos.json  # Snapshot de vehículos en servicio
```

### 3.3. Botón de Exportación en el Panel de Garita
Para que la administración de Transportes Serrano posea control autónomo sin depender de desarrolladores, el panel web/móvil de Garita incluye la acción **"Exportar Datos de Línea"**, que descarga un archivo comprimido `.json` con la totalidad de sus recorridos y paraderos al almacenamiento local del equipo.

---

## 4. Propuesta 2: Historización y Auditoría de Telemetría (Realtime Database)

Un respaldo tradicional de una base de datos en tiempo real resulta ineficiente: guardar millones de coordenadas individuales cada 3 segundos satura el almacenamiento y genera costos innecesarios.

La solución de ingeniería implementada aborda la telemetría en dos fases:

### 4.1. Bitácora Consolidada al Cierre de Turno (*Turn Summary Logging*)
Mientras el colectivo circula, las coordenadas viajan únicamente por WebSockets hacia Realtime Database (efímero, latencia < 300 ms, costo $0). 

Cuando el conductor presiona **"Finalizar Turno"**:
* La aplicación calcula el resumen operativo de la jornada:
  * Horario exacto de inicio y término.
  * Tiempo total en servicio y tiempo en cada estado de capacidad (disponible, medio lleno, lleno).
  * Distancia total recorrida estimada sobre el trazado.
* Este resumen se almacena como un registro permanente en la colección `turnos_historicos` de Firestore o en un archivo local de auditoría.

### 4.2. Sifón Local en la Garita (*Local Telemetry Siphon*)
Como el computador de la Garita mantiene abierta la pantalla de supervisión de flota, un proceso en segundo plano almacena en un archivo `.csv` local las emisiones de los colectivos activos. 

Esto entrega un registro histórico continuo para responder reclamos de usuarios o fiscalizaciones del Ministerio de Transportes (MTT) con costo de infraestructura cero.

---

## 5. Propuesta 3: Desacoplamiento de Software (Patrón Repositorio en Flutter)

Para eliminar el *Vendor Lock-in* a nivel de código fuente, la aplicación no debe acoplarse directamente a los SDKs de Firebase (`FirebaseFirestore.instance`).

Se formaliza la adopción del **Patrón Repositorio (*Repository Pattern*)** mediante contratos e interfaces abstractas en Dart:

```dart
// 1. Contrato abstracto puro (agnóstico de la nube)
abstract class IStopsRepository {
  Future<List<BusStop>> getStops();
  Stream<List<BusStop>> watchStops();
  Future<void> saveStop(BusStop stop);
}

// 2. Implementación primaria con Firebase
class FirebaseStopsRepository implements IStopsRepository {
  @override
  Stream<List<BusStop>> watchStops() {
    return FirebaseFirestore.instance.collection('paraderos').snapshots().map(...);
  }
  // ...
}

// 3. Implementación alternativa (Migración transparente a Supabase o SQLite local)
class SupabaseStopsRepository implements IStopsRepository {
  @override
  Stream<List<BusStop>> watchStops() {
    return supabase.from('paraderos').stream(primaryKey: ['id']).map(...);
  }
}
```

### Impacto Arquitectónico:
La lógica de negocio (`StopsService`) y las pantallas de Flutter interactúan únicamente con `IStopsRepository`. Si la empresa decide migrar a **Supabase, CouchDB o un servidor PostgreSQL propio**, solo se reemplaza la clase repositorio concreta en la inicialización sin tocar una sola línea de la interfaz de usuario ni de los algoritmos de recomendación.

---

## 6. Plan de Recuperación ante Desastres (Disaster Recovery Blueprint)

Se establecen las métricas operacionales de continuidad de negocio:

| Métrica | Definición | Objetivo ColeTotal | Justificación Técnica |
| :--- | :--- | :--- | :--- |
| **RPO (Recovery Point Objective)** | Pérdida máxima admisible de datos ante caída. | **< 24 Horas** para datos maestros.<br>**< 1 Turno** para telemetría. | Los paraderos y rutas cambian muy rara vez. El respaldo diario cubre el 100% de los cambios viales. |
| **RTO (Recovery Time Objective)** | Tiempo máximo para restaurar la operación del sistema. | **< 30 Minutos** | Mediante el script de migración, los archivos JSON se cargan en una instancia de respaldo en minutos. |

### Procedimiento Operativo de Emergencia (SOP):
1. **Detección:** Caída mayor reportada en la región `us-central1` de Google Cloud.
2. **Modo Autónomo Local (Cero Interrupción para el Pasajero):** Los usuarios siguen consultando paraderos y trazados gracias a la **semilla síncrona en memoria y la caché SQLite en disco** del dispositivo (OE2).
3. **Restauración:** Ejecución del script de inyección sobre la base de datos de contingencia (ej. Supabase) y actualización del puntero en el repositorio abstracto.

---

## 7. Argumentación para la Defensa Oral ante la Comisión

Si el profesor **Francisco Ponce** o la profesora **Claudia Vasconcellos** interrogan al equipo sobre la dependencia de la nube:

> *"Profesor, abordamos su observación de manera integral en tres niveles:*
>
> 1. *En la **Soberanía de Datos**, garantizamos que Transportes Serrano no sea cautivo de Google. Diseñamos un mecanismo de extracción periódica que convierte paraderos y recorridos a formatos abiertos estándar (JSON y GeoJSON espacial RFC 7946), permitiendo migrar la infraestructura a cualquier base de datos relacional en menos de media hora.*
> 2. *En la **Telemetría**, distinguimos la coordinación efímera del segundo a segundo respecto a la auditoría histórica. Al cerrar turno, se consolida una bitácora operacional en almacenamiento persistente, evitando sobrecostos de almacenamiento sin perder trazabilidad.*
> 3. *En la **Arquitectura de Software**, implementamos el Patrón Repositorio en Flutter, desacoplando los widgets de los SDKs de Firebase. Si la línea decide cambiar de proveedor cloud, la aplicación está preparada para intercambiar adaptadores sin alterar su lógica ni su diseño."*
