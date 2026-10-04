# 🚖 ColeTotal — Lista de Usuarios y Credenciales de Prueba
> **Piloto Operacional:** Línea 1 Transportes Serrano S.A. (Quilpué)  
> **Versión del Sistema:** v0.4.3.1 (Build 4)  
> **Fecha de Emisión:** Octubre 2026  

Este documento reúne todas las cuentas configuradas en Firebase Authentication y Cloud Firestore para pruebas de campo, demostraciones y auditoría del sistema ColeTotal.

---

## 🔑 Códigos de Acceso (Enrolamiento de Nuevos Usuarios)

Para crear cuentas nuevas directamente desde la aplicación sin intervención manual:

| Tipo de Cuenta | Código Secreto | Destino / Permisos | Uso |
| :--- | :--- | :--- | :--- |
| **Chofer de Colectivo** | `CHOFERSERRANOS` | Vincula a `garita_quilpue_01` con rol `colectivero` | Pantalla de Registro -> Rol Chofer |
| **Administrador / Garitero** | `MEGADMIN5TA` | Vincula a `garita_quilpue_01` con rol `administrador` | Pantalla de Registro -> Rol Garita |

---

## 👨‍💼 1. Cuentas de Administrador (Inspectores de Garita / Gerencia)

Permiten acceder a la consola de gestión de flota, creación de recorridos, supervisión de paraderos y auditoría de choferes.

| Nombre | Correo Electrónico | Contraseña | Rol | Garita Asignada |
| :--- | :--- | :--- | :--- | :--- |
| **Marco Fernandoy** | `marco.fernandoy.rojas@gmail.com` | *(Tu clave personal Google / Firebase)* | Administrador | Garita Cumming (`garita_quilpue_01`) |
| **Tomás Moraga** | `tomas76moraga@gmail.com` | *(Su clave personal Google / Firebase)* | Administrador | Garita Cumming (`garita_quilpue_01`) |

---

## 🚕 2. Cuentas de Choferes de Prueba (Flota Serrano)

> **Contraseña universal para todos los choferes de prueba:** `Chofer1234!`  
> **Nota de inicio de sesión:** En la pantalla de login, el chofer puede ingresar escribiendo directamente su **Patente** (ej. `IB12BI` o `IB-12-BI`) o su correo electrónico sintético.

| Patente | Nombre del Conductor | Correo en Firebase | Contraseña | Estado Inicial | Recorrido Típico |
| :---: | :--- | :--- | :---: | :---: | :--- |
| **IB12BI** | Matías Fuentes | `ib12bi@chofer.coletotal.app` | `Chofer1234!` | 🟢 **En Servicio** (Lleno) | Línea 101: Valencia - Los Carrera |
| **JHTB45** | Carlos Soto Muñoz | `jhtb45@chofer.coletotal.app` | `Chofer1234!` | 🟢 **En Servicio** (Disponible) | Línea 102: Belloto Sur - Centro |
| **KPVD82** | Manuel Riquelme Peña | `kpvd82@chofer.coletotal.app` | `Chofer1234!` | 🟢 **En Servicio** (Medio Lleno) | Línea 103: Belloto 2000 - Freire |
| **LRFX19** | Roberto González Araya | `lrfx19@chofer.coletotal.app` | `Chofer1234!` | ⚪ Fuera de servicio | Línea 104: Los Pinos - El Sol |
| **BDGT57** | Juan Plaza Castro | `bdgt57@chofer.coletotal.app` | `Chofer1234!` | ⚪ Fuera de servicio | Línea 105: Villa Olímpica - Plaza Vieja |
| **FPZK33** | Patricio Valenzuela Vera | `fpzk33@chofer.coletotal.app` | `Chofer1234!` | ⚪ Fuera de servicio | Línea 106: Pompeya - Troncal Urbano |
| **ABCD12** | Pedro Morales Vera | `abcd12@chofer.coletotal.app` | `Chofer1234!` | 🔴 **Deshabilitado** | *Cuenta de prueba de bloqueo de garita* |

### ¿Para qué sirve la cuenta de Pedro Morales (`ABCD12`)?
Se dejó intencionalmente con `activo: false` en Firestore para demostrar en la defensa del proyecto cómo un inspector de garita puede suspender a un chofer infractor o con cuota impaga: al intentar iniciar turno, la aplicación le muestra: *"Tu cuenta está deshabilitada. Habla con tu garita."*.

---

## 🧭 3. Terminales de Garita Configuradas en el Sistema

Transportes Serrano opera con 3 garitas en Quilpué, representadas en los filtros multi-garita de la consola de administración:

1. **Garita Cumming (`garita_quilpue_01`):** Terminal principal donde se ejecuta el piloto.
2. **Garita Las Rosas (`garita_serranos_rosas`):** Terminal sector norte.
3. **Garita Belloto 2000 (`garita_serranos_belloto2000`):** Terminal Belloto.

---

## 📱 4. Pasos para Probar la App en Terreno

1. **Como Pasajero:** Abre la app sin iniciar sesión (Modo Invitado). Verás los colectivos transmitiendo en tiempo real sobre el mapa de Quilpué y podrás buscar destinos (ej. *"Líder Belloto"* o *"Hospital"*).
2. **Como Chofer:** Inicia sesión con la patente `JHTB45` y clave `Chofer1234!`. Ve a la pestaña **Turno**, selecciona un recorrido, presiona **Iniciar Turno** y cambia el estado de capacidad (Disponible / Medio / Lleno).
3. **Como Administrador:** Inicia sesión con la cuenta de Marco o Tomás. Ve a la pestaña **Flota** para ver la totalidad de vehículos en servicio, filtrando por garita o seleccionando cualquier colectivo para inspeccionar su trazado.
