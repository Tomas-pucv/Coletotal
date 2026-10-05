# 🚖 ColeTotal — Cuentas de Prueba
> **Piloto Operacional:** Línea 1 Transportes Serrano S.A. (Quilpué)  
> **Versión del Sistema:** `0.4.3+4`  
> **Fecha de Emisión:** Octubre 2026  

Este documento describe las cuentas configuradas para pruebas de campo, demostraciones y auditoría del sistema ColeTotal.

> [!IMPORTANT]
> **Los códigos de garita y las contraseñas no se escriben en el repositorio.** Un código de administrador permite registrarse como administrador de la garita y gestionarla entera (paraderos, recorridos, choferes, auditoría), y el repositorio se comparte.
>
> Los códigos y la contraseña de los choferes de prueba que estuvieron en versiones anteriores de este archivo y de `scripts/seed_dummy_data.js` siguen en el historial de git: **hay que rotarlos** (crear códigos nuevos en `codigos_acceso`, desactivar los viejos con `activo: false` y cambiar las contraseñas de las cuentas de prueba).
>
> Las credenciales vigentes se entregan por un canal privado.

---

## 🔑 Códigos de Acceso (Enrolamiento de Nuevos Usuarios)

| Tipo de Cuenta | Código | Destino / Permisos | Uso |
| :--- | :--- | :--- | :--- |
| **Chofer de Colectivo** | *(entregado por la garita)* | `garita_quilpue_01`, rol `colectivero` | Registro → "Colectivero" |
| **Administrador de Garita** | *(entregado por el equipo)* | `garita_quilpue_01`, rol `administrador` | Registro → "Administrador" |

Para crearlos en un proyecto de pruebas se usa el script, con los valores en variables de entorno:

```bash
CHOFER_CODE=... ADMIN_CODE=... TEST_DRIVER_PASSWORD=... node scripts/seed_dummy_data.js
```

---

## 👨‍💼 1. Cuentas de Administrador

Cada integrante del equipo tiene su propia cuenta de administrador de la Garita Cumming (`garita_quilpue_01`), con su correo y contraseña personales.

---

## 🚕 2. Cuentas de Choferes de Prueba (Flota Serrano)

Las crea `scripts/seed_dummy_data.js`, todas con la contraseña de `TEST_DRIVER_PASSWORD`. Se inicia sesión con la **patente** (con o sin guiones).

| Patente | Nombre del Conductor | Estado Inicial | Recorrido Típico |
| :---: | :--- | :---: | :--- |
| **IB12BI** | Matías Fuentes | 🟢 **En Servicio** (Lleno) | Línea 101: Valencia - Los Carrera |
| **JHTB45** | Carlos Soto Muñoz | 🟢 **En Servicio** (Disponible) | Línea 102: Belloto Sur - Centro |
| **KPVD82** | Manuel Riquelme Peña | 🟢 **En Servicio** (Medio Lleno) | Línea 103: Belloto 2000 - Freire |
| **LRFX19** | Roberto González Araya | ⚪ Fuera de servicio | Línea 104: Los Pinos - El Sol |
| **BDGT57** | Juan Plaza Castro | ⚪ Fuera de servicio | Línea 105: Villa Olímpica - Plaza Vieja |
| **FPZK33** | Patricio Valenzuela Vera | ⚪ Fuera de servicio | Línea 106: Pompeya - Troncal Urbano |
| **ABCD12** | Pedro Morales Vera | 🔴 **Deshabilitado** | *Cuenta de prueba de bloqueo de garita* |

Las tres unidades "En Servicio" son posiciones sembradas en Realtime Database: aparecen en el mapa durante 3 minutos después de correr el script y luego desaparecen, porque nadie las actualiza.

### ¿Para qué sirve la cuenta de Pedro Morales (`ABCD12`)?
Está con `activo: false` para demostrar cómo la garita suspende a un chofer: al intentar iniciar sesión, la app muestra *"Tu cuenta está deshabilitada. Habla con tu garita."*. Y si se deshabilita a un chofer que está en turno, su app cierra la sesión en segundos y deja de transmitir.

---

## 🧭 3. Terminales de Garita

Transportes Serrano opera con 3 garitas en Quilpué. La consola de flota arma su filtro con los documentos de la colección `garitas`:

1. **Garita Cumming (`garita_quilpue_01`):** terminal principal donde se ejecuta el piloto.
2. **Garita Las Rosas (`garita_serranos_rosas`):** terminal sector norte.
3. **Garita Belloto 2000 (`garita_serranos_belloto2000`):** terminal Belloto.

---

## 📱 4. Pasos para Probar la App en Terreno

1. **Como Pasajero:** abre la app sin iniciar sesión (modo invitado). Verás los colectivos transmitiendo en tiempo real y podrás buscar destinos (ej. *"lider belloto"* o *"hospital"*). Toca un colectivo para ver su línea.
2. **Como Chofer:** inicia sesión con una patente de prueba. En la pestaña **Turno**, elige el recorrido, presiona **Iniciar turno** (aparece la notificación "ColeTotal — en servicio") y cambia la capacidad (Disponible / Medio / Lleno).
3. **Como Administrador:** inicia sesión con tu cuenta. En **Flota** verás las unidades en servicio; filtra por garita o toca una unidad para ver su recorrido. En **Garita → Choferes**, deshabilita a un chofer en turno y observa cómo su unidad deja de transmitir.
