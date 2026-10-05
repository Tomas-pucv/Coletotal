# ColeTotal 🚖

Aplicación móvil para la gestión de paraderos, recorridos y flotas de **taxis
colectivos** en la Región de Valparaíso, con foco inicial en Transportes
Serrano (Quilpué).

El pasajero ve dónde vienen los colectivos y a qué paradero le conviene ir; el
conductor transmite su posición durante su turno; el administrador de garita
gestiona los datos de la línea y supervisa la flota en vivo.

Proyecto de título — Escuela de Ingeniería Informática, Pontificia Universidad
Católica de Valparaíso.

---

## Perfiles de usuario

La app tiene tres perfiles, y el menú lateral muestra en todo momento cuál está
activo y qué permite hacer.

| Perfil | Cómo se entra | Para qué sirve |
|---|---|---|
| **Invitado** | Sin registro | Consultar el mapa, buscar paraderos y ver los colectivos en circulación |
| **Colectivero** | Patente + contraseña | Transmitir su posición a los pasajeros y a la garita durante el turno |
| **Administrador de garita** | Correo + contraseña | Gestionar paraderos, recorridos y choferes, y monitorear la flota |

Los dos perfiles con cuenta se registran con un **código de garita** que entrega
el administrador. El código determina el rol: no se elige en el formulario, y
las reglas de Firestore lo verifican en el servidor al crear la cuenta.

## Funcionalidades

### Pasajero (no requiere cuenta)

- Mapa interactivo con seguimiento de la ubicación, recentrado, zoom y rotación.
- **Colectivos en vivo** sobre el mapa, coloreados según la capacidad que
  reporta cada chofer (disponible / medio lleno / lleno). Una unidad que lleva
  más de 45 s sin señal se dibuja atenuada, y a los 3 min desaparece.
- Al tocar un colectivo: su patente, su capacidad, hace cuánto se lo vio y,
  si el chofer la informó, su línea dibujada sobre el mapa.
- **Buscador de direcciones**: se escribe a dónde se quiere ir y la app
  recomienda el paradero, ordenando por el promedio de los dos tramos a pie
  (lo que se camina hasta el paradero y lo que se camina desde la bajada).
  Incluye un catálogo local de 26 lugares de Quilpué y no distingue tildes
  ("lider" encuentra "Líder").
- Lista de **paraderos** ordenada por cercanía a la posición actual o por los
  últimos consultados.
- Al tocar un paradero: los colectivos que pasan por él; al tocar una línea, su
  recorrido dibujado sobre el mapa.
- **Ruta a pie** hasta el paradero desde la posición actual, con distancia y
  tiempo caminando.

### Colectivero

- Pantalla de turno con un interruptor grande **En servicio / Fuera de
  servicio**.
- Elección del **recorrido** que se está cubriendo (se recuerda entre turnos y
  se puede cambiar en pleno turno).
- Selector de capacidad de un toque, que alimenta la semaforización que ven
  pasajeros y garita.
- Transmisión GPS en segundo plano mientras el turno está activo, con
  servicio en primer plano y notificación persistente.
- Confirmación en vivo ("última posición enviada hace 3 s") y aviso cuando no
  hay señal; la posición se reenvía sola al recuperarla.
- Auditoría del turno (pérdidas de GPS y de señal, cambios de capacidad y de
  recorrido) que se sube a Firestore al terminar, también si la app se cerró
  a mitad del turno.
- Aviso de consentimiento de geolocalización (Ley 19.628).

### Administrador de garita

- Portada con métricas: unidades en servicio, paraderos y recorridos.
- **Paraderos**: crear, mover sobre el mapa, editar, dar de baja y reactivar.
- **Recorridos**: nombre, color y lista ordenada de paraderos; el trazado se
  calcula siguiendo las calles entre ellos y se recalcula al mover un paradero.
- **Choferes**: padrón de la garita con indicador de quién está en servicio e
  interruptor para habilitar o deshabilitar el acceso. Deshabilitar a un
  chofer cierra su sesión (y su turno) en segundos.
- **Flota**: mapa y lista en vivo de las unidades, con su estado, hace cuánto
  se las vio y, al tocar una, su recorrido. Se puede filtrar por garita.
- Sin señal, los cambios se guardan igual y se sincronizan al volver la red.

### Transversal

- Interfaz en español, adaptable a teléfono y tablet (barra inferior o rail
  lateral según el ancho).
- Tema claro / oscuro / automático, ajuste de tamaño de fuente y modo compacto.
- Los paraderos se muestran sin conexión gracias a una semilla local y a la
  caché offline de Firestore.
- Ninguna acción espera indefinidamente al servidor: sin señal, terminar el
  turno, cerrar sesión o guardar un cambio terminan en segundos y lo
  pendiente se sincroniza después.

## Stack tecnológico

| Herramienta | Rol |
|---|---|
| Flutter / Dart | Desarrollo multiplataforma |
| `flutter_map` + `flutter_map_animations` | Mapa interactivo y animaciones de cámara |
| MapTiler | Teselas cartográficas y geocodificación de direcciones |
| `geolocator` | GPS del dispositivo y seguimiento en segundo plano |
| Firebase Authentication | Sesiones de choferes y administradores |
| Cloud Firestore | Usuarios, garitas, paraderos y recorridos |
| Firebase Realtime Database | Telemetría GPS de alta frecuencia |
| OSRM (FOSSGIS a pie, demo en auto) / OpenRouteService | Rutas a pie y trazado de los recorridos |
| `shared_preferences` | Preferencias e historial local |

**Requisitos:** Flutter ≥ 3.44, Dart ≥ 3.12. Probado en Android; iOS necesita
además `ios/Runner/GoogleService-Info.plist`, que no está en el repositorio.

## Puesta en marcha

```bash
flutter pub get
flutter gen-l10n
flutter run
```

La app arranca como Invitado y muestra el mapa con paraderos de referencia sin
necesidad de configurar nada. Para que funcionen el registro, los recorridos y
el panel de garita hay que preparar el proyecto de Firebase:

1. **Authentication → Sign-in method**: habilitar *Correo electrónico/contraseña*.
2. **Firestore Database**: crearla en modo producción (la región es permanente).
3. **Desplegar las reglas**, que están versionadas en el repositorio:
   ```bash
   firebase deploy --only firestore:rules,database
   ```
4. **Sembrar los datos mínimos** desde la consola:
   - `garitas/{id}` → `{ nombre, comuna }`
   - `codigos_acceso/{CÓDIGO}` → `{ garitaId, rol: "colectivero", activo: true }`
   - otro `codigos_acceso` con `rol: "administrador"`

   El id del documento **es** el código que se entrega a la persona, así que
   conviene que sea largo, no adivinable y en mayúsculas (p. ej.
   `SERRANO-CHO-7K4M9`). Los códigos **no** se guardan en el repositorio: el
   script de datos de prueba los recibe por variables de entorno
   (`CHOFER_CODE`, `ADMIN_CODE`, `TEST_DRIVER_PASSWORD`).
5. Entrar como administrador y cargar los paraderos (hay un botón para importar
   los de ejemplo) y los recorridos de la línea.

Sin el paso 5, la búsqueda de direcciones funciona, pero la ficha de paradero no
tiene colectivos que mostrar y la recomendación cae a ordenar por cercanía.

### Claves de API

La clave de MapTiler tiene un valor por defecto en el código y se puede
sobreescribir sin tocarlo:

```bash
flutter run --dart-define=MAPTILER_KEY=tu_clave
flutter run --dart-define=ORS_API_KEY=tu_clave   # opcional: mejora el ruteo
```

Sin `ORS_API_KEY` el ruteo cae al servidor público de demostración de OSRM, que
funciona pero no ofrece garantías de servicio.

## Estructura del proyecto

```
lib/
├── config/       Clave y estilos de MapTiler, centro del mapa
├── l10n/         Textos en español (ARB + generados)
├── models/       AppUser, BusStop, Recorrido, ColectivoActivo, Garita
├── navigation/   Destinos y qué ve cada rol
├── screens/      admin/ · auth/ · driver/ · mapa, paraderos, preferencias
├── services/     Estado de la app en singletons ChangeNotifier (sesión,
│                 paraderos, recorridos, telemetría, turno) más utilidades sin
│                 estado (geocodificación, planificador de paraderos, OSRM)
├── theme/        Tema Material 3, colores semánticos, espaciado
├── utils/        Formato de distancias, patentes, errores
└── widgets/      Menú lateral, hojas de paradero y sugerencias, buscador
```

Verificación: `flutter analyze` y `flutter test` (134 pruebas, sin red ni
Firebase). Entre ellas hay pruebas de contrato que leen `firestore.rules` y
`database.rules.json` y fallan si el cliente escribe un campo que las reglas
rechazarían.

## Publicar una versión

1. Subir `version:` en `pubspec.yaml` (p. ej. `0.4.4+5`). Es la única fuente:
   la app la lee del propio APK para compararla con la publicada.
2. Firmar siempre con la **misma** llave, o Android rechaza el APK nuevo
   encima del instalado. La llave se crea una sola vez y se guarda fuera del
   repositorio:
   ```bash
   keytool -genkey -v -keystore coletotal-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias coletotal
   ```
   y `android/key.properties` (ignorado por git):
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=coletotal
   storeFile=C:/ruta/a/coletotal-release.jks
   ```
   Sin ese archivo el APK se firma con la llave de debug del computador.
3. `flutter build apk --release` y subir el APK (se recomienda GitHub
   Releases).
4. Publicar el aviso de actualización:
   ```bash
   APK_URL=https://.../ColeTotal.apk CHANGELOG="• ..." node scripts/seed_app_version.js
   ```
   Con `MIN_REQUIRED=n` las versiones anteriores a `n` ven la actualización
   como obligatoria.

## Limitaciones conocidas

- **Sin recuperación de contraseña para choferes.** La patente se traduce a un
  correo sintético que no recibe mensajes; si un chofer pierde su contraseña,
  el administrador deshabilita la cuenta y le entrega un código nuevo.
- **El sentido de marcha no se modela.** Un recorrido se trata como el conjunto
  de sus paraderos, así que la recomendación asume que desde la subida se
  alcanza cualquier otra parada de esa línea.
- **El cálculo de ETA todavía no está implementado.**
- Las reglas de Realtime Database no pueden consultar Firestore: no saben si un
  chofer está deshabilitado, y el `garitaId` de la telemetría se filtra del
  lado del cliente. La app cierra la sesión de un chofer deshabilitado en
  cuanto la garita lo marca, pero las reglas por sí solas no lo impedirían.
- La notificación del turno necesita, en Android 13 o superior, el permiso de
  notificaciones; sin él el servicio sigue transmitiendo, pero la
  notificación no se ve.

## Descargas

Obtener la última versión del APK en la sección
[releases](https://github.com/Tomas-pucv/Coletotal/releases).
