// scripts/seed_dummy_data.js
// Poblamiento de datos de prueba para ColeTotal (Quilpué).
//
// Los códigos de garita y la contraseña de los choferes de prueba ya no están
// escritos en el repositorio: los códigos dan acceso real (el de administrador
// permite gestionar la garita entera) y el repositorio se comparte.
//
// Uso:
//   CHOFER_CODE=... ADMIN_CODE=... TEST_DRIVER_PASSWORD=... //   node scripts/seed_dummy_data.js
// Requiere haber hecho `firebase login` con una cuenta con acceso al proyecto.

const { PROJECT_ID, getAccessToken, patchDocument, requireEnv } = require('./lib/firebase_rest');

// Clave web pública de Firebase (la misma de lib/firebase_options.dart): no es
// un secreto, identifica al proyecto ante la API de Identity Toolkit.
const API_KEY = 'AIzaSyC6IOk1pmwqqZq-ZI9tpTSnV61BCGMcB54';
const GARITA_ID = 'garita_quilpue_01';

const CHOFER_CODE = requireEnv('CHOFER_CODE', 'Código de garita para choferes (largo y no adivinable).');
const ADMIN_CODE = requireEnv('ADMIN_CODE', 'Código de garita para administradores (largo y no adivinable).');
const STANDARD_PASSWORD = requireEnv('TEST_DRIVER_PASSWORD', 'Contraseña de las cuentas de choferes de prueba.');

function setFirestoreDoc(token, collection, docId, data) {
  return patchDocument(token, `${collection}/${docId}`, data);
}

async function createOrGetAuthUser(email, password, displayName) {
  // 1. Try signUp
  const signUpRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password,
        displayName,
        returnSecureToken: true,
      }),
    }
  );
  const signUpData = await signUpRes.json();
  if (signUpRes.ok && signUpData.localId) {
    return signUpData.localId;
  }

  // 2. If already exists, signIn to get UID
  if (signUpData.error && signUpData.error.message.includes('EMAIL_EXISTS')) {
    const signInRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email,
          password,
          returnSecureToken: true,
        }),
      }
    );
    const signInData = await signInRes.json();
    if (signInRes.ok && signInData.localId) {
      return signInData.localId;
    }
  }

  throw new Error(`Error createOrGetAuthUser (${email}): ${JSON.stringify(signUpData)}`);
}

// PATCH y no PUT: un PUT sobre `colectivos_activos` reemplazaba el nodo entero
// y sacaba del mapa a los choferes reales que estuvieran en turno.
async function setRtdbData(token, path, data) {
  const url = `https://${PROJECT_ID}-default-rtdb.firebaseio.com/${path}.json?access_token=${token}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Error setRtdbData [${path}]: ${res.status} ${errText}`);
  }
  return res.json();
}

async function main() {
  console.log('🚀 Iniciando siembra de datos dummies para ColeTotal...');
  const token = await getAccessToken();
  console.log('🔑 Token de acceso a Firebase obtenido.');

  // 1. Garita Central
  console.log('\n--- 1. Verificando Garita ---');
  await setFirestoreDoc(token, 'garitas', GARITA_ID, {
    nombre: 'Línea 1 Transportes Serrano S.A.',
    comuna: 'Quilpué',
  });
  console.log(`✅ Garita '${GARITA_ID}' configurada.`);

  // 2. Códigos de Acceso
  console.log('\n--- 2. Verificando Códigos de Acceso ---');
  // El id del documento ES el código. La app lo busca en mayúsculas.
  await setFirestoreDoc(token, 'codigos_acceso', CHOFER_CODE.toUpperCase(), {
    activo: true,
    garitaId: GARITA_ID,
    rol: 'colectivero',
  });
  await setFirestoreDoc(token, 'codigos_acceso', ADMIN_CODE.toUpperCase(), {
    activo: true,
    garitaId: GARITA_ID,
    rol: 'administrador',
  });
  console.log('✅ Códigos de chofer y de administrador configurados.');

  // 3. Paraderos adicionales en Quilpué (8 nuevos estratégicos)
  console.log('\n--- 3. Sembrando Paraderos en Quilpué ---');
  const paraderosNuevos = [
    {
      id: 'stop-belloto-2000',
      nombre: 'Belloto 2000',
      direccion: 'Av. Freire / Av. V Centenario',
      lat: -33.0515,
      lng: -71.4250,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-valencia',
      nombre: 'Valencia',
      direccion: 'Av. Los Carrera 350, Valencia',
      lat: -33.0420,
      lng: -71.4610,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-marga-marga-sur',
      nombre: 'Marga Marga Sur',
      direccion: 'Av. Marga Marga 2200, Quilpué',
      lat: -33.0590,
      lng: -71.4550,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-plaza-vieja',
      nombre: 'Plaza Vieja',
      direccion: 'Manuel Rodríguez 850, Quilpué',
      lat: -33.0455,
      lng: -71.4465,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-terminal-serrano',
      nombre: 'Garita Serrano',
      direccion: 'Serrano 1420, Quilpué',
      lat: -33.0645,
      lng: -71.4390,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-portal-belloto',
      nombre: 'Portal El Belloto',
      direccion: 'Av. Freire 2411, Quilpué',
      lat: -33.0485,
      lng: -71.4180,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-los-pinos',
      nombre: 'Los Pinos',
      direccion: 'Av. Marga Marga / Los Pinos',
      lat: -33.0620,
      lng: -71.4580,
      garitaId: GARITA_ID,
      activo: true,
    },
    {
      id: 'stop-pompeya-sur',
      nombre: 'Pompeya Sur',
      direccion: 'Las Américas 120, Quilpué',
      lat: -33.0540,
      lng: -71.4680,
      garitaId: GARITA_ID,
      activo: true,
    },
  ];

  for (const p of paraderosNuevos) {
    await setFirestoreDoc(token, 'paraderos', p.id, {
      nombre: p.nombre,
      direccion: p.direccion,
      lat: p.lat,
      lng: p.lng,
      garitaId: p.garitaId,
      activo: p.activo,
    });
    console.log(`  📍 Paradero añadido: ${p.nombre} (${p.id})`);
  }

  // 4. Los 7 Recorridos oficiales de Quilpué
  console.log('\n--- 4. Creando 7 Recorridos Oficiales ---');
  const recorridos = [
    {
      id: 'recorrido-101-valencia-hospital',
      nombre: 'Línea 101: Valencia - Los Carrera - Hospital',
      color: 4283056030, // 0xFF4A3F9E Índigo
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'stop-valencia',
        'HP64aCEKE62hH3oFh79L', // Claudio Arrau
        'aI1NqSWUNPIspDbYO0GF', // Colon
        'dk5BH53eISPaGRhcckPr', // Plaza de Armas
        'qndlGOHDC8XX4xh96QT7', // Hospital Quilpué
      ],
    },
    {
      id: 'recorrido-102-belloto-centro',
      nombre: 'Línea 102: Belloto Sur - Marga Marga - Centro',
      color: 4286267296, // 0xFF7B3FA0 Violeta
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'stop-terminal-serrano',
        'gpyHpH5i7LebBQHESlIk', // Arturo Alessandri
        'I0jjhDLOVQEytVeW9NRJ', // Belloto
        'dk5BH53eISPaGRhcckPr', // Plaza de Armas
        'Awwtn1GKE6TXwQiMH9IB', // Estación Quilpué
      ],
    },
    {
      id: 'recorrido-103-belloto2000-estacion',
      nombre: 'Línea 103: Belloto 2000 - Freire - Estación',
      color: 4289737610, // 0xFFB0338A Magenta
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'stop-portal-belloto',
        'stop-belloto-2000',
        'gIX0kZoAulXiNhNYnole', // El Sol
        'EFHzKcdBtgrGYov8hd9R', // Freire
        'Awwtn1GKE6TXwQiMH9IB', // Estación Quilpué
      ],
    },
    {
      id: 'recorrido-104-lospinos-elsol',
      nombre: 'Línea 104: Los Pinos - El Sol - Plaza de Armas',
      color: 4278219388, // 0xFF00727C Teal oscuro
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'stop-los-pinos',
        'stop-marga-marga-sur',
        'iqKiKsZa3OYjcWZfdM9C', // Vicuña Mackenna
        'gIX0kZoAulXiNhNYnole', // El Sol
        'dk5BH53eISPaGRhcckPr', // Plaza de Armas
      ],
    },
    {
      id: 'recorrido-105-olimpica-plazavieja',
      nombre: 'Línea 105: Villa Olímpica - Retiro - Plaza Vieja',
      color: 4284301367, // 0xFF5D4037 Café
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'X6TnI2kxpcZAnV9XMsCC', // Villa Olimpica
        'stop-plaza-vieja',
        'aI1NqSWUNPIspDbYO0GF', // Colon
        'EFHzKcdBtgrGYov8hd9R', // Freire
        'Awwtn1GKE6TXwQiMH9IB', // Estación Quilpué
      ],
    },
    {
      id: 'recorrido-106-pompeya-troncal',
      nombre: 'Línea 106: Pompeya - Hospital - Troncal Urbano',
      color: 4281812815, // 0xFF37474F Gris azulado
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'stop-pompeya-sur',
        'qndlGOHDC8XX4xh96QT7', // Hospital Quilpué
        'HP64aCEKE62hH3oFh79L', // Claudio Arrau
        'dk5BH53eISPaGRhcckPr', // Plaza de Armas
        'stop-valencia',
      ],
    },
    {
      id: 'recorrido-107-directo-portal-serrano',
      nombre: 'Línea 107: Directo Portal Belloto - Centro - Garita Serrano',
      color: 4280171146, // 0xFF1E3A8A Azul marino
      garitaId: GARITA_ID,
      activo: true,
      paraderoIds: [
        'stop-portal-belloto',
        'stop-belloto-2000',
        'Awwtn1GKE6TXwQiMH9IB', // Estación Quilpué
        'dk5BH53eISPaGRhcckPr', // Plaza de Armas
        'Y2uIFOx4QhqweOOMwMP6', // Villa Cumming
        'stop-terminal-serrano',
      ],
    },
  ];

  for (const r of recorridos) {
    await setFirestoreDoc(token, 'recorridos', r.id, {
      nombre: r.nombre,
      color: r.color,
      garitaId: r.garitaId,
      activo: r.activo,
      paraderoIds: r.paraderoIds,
    });
    console.log(`  🛣️ Recorrido guardado: ${r.nombre}`);
  }

  // 5. Cuentas de Chofer (7 choferes)
  console.log('\n--- 5. Configurando 7 Cuentas de Chofer en Firebase Auth + Firestore ---');
  const choferes = [
    {
      patente: 'IB12BI',
      nombre: 'Matías Fuentes',
      activo: true,
      enServicio: true,
      lat: -33.0595,
      lng: -71.4552,
      estado: 'lleno',
    },
    {
      patente: 'JHTB45',
      nombre: 'Carlos Soto Muñoz',
      activo: true,
      enServicio: true,
      lat: -33.0470,
      lng: -71.4420,
      estado: 'disponible',
    },
    {
      patente: 'KPVD82',
      nombre: 'Manuel Riquelme Peña',
      activo: true,
      enServicio: true,
      lat: -33.0450,
      lng: -71.4405,
      estado: 'medioLleno',
    },
    {
      patente: 'LRFX19',
      nombre: 'Roberto González Araya',
      activo: true,
      enServicio: false,
    },
    {
      patente: 'BDGT57',
      nombre: 'Juan Plaza Castro',
      activo: true,
      enServicio: false,
    },
    {
      patente: 'FPZK33',
      nombre: 'Patricio Valenzuela Vera',
      activo: true,
      enServicio: false,
    },
    {
      patente: 'ABCD12',
      nombre: 'Pedro Morales Vera',
      activo: false, // ¡Deshabilitado a propósito para demo de interruptor!
      enServicio: false,
    },
  ];

  const colectivosActivosRTDB = {};

  for (const c of choferes) {
    const email = `${c.patente.toLowerCase()}@chofer.coletotal.app`;
    console.log(`  👤 Procesando chofer: ${c.nombre} (${c.patente})...`);
    
    // Auth account
    let uid;
    try {
      uid = await createOrGetAuthUser(email, STANDARD_PASSWORD, c.nombre);
    } catch (e) {
      console.error(`    ⚠️ Error creando Auth para ${c.patente}:`, e.message);
      continue;
    }

    // Firestore profile
    await setFirestoreDoc(token, 'usuarios', uid, {
      nombre: c.nombre,
      rol: 'colectivero',
      garitaId: GARITA_ID,
      patente: c.patente,
      activo: c.activo,
      codigo: CHOFER_CODE.toUpperCase(),
    });
    console.log(`    ✅ Perfil en Firestore [usuarios/${uid}] actualizado.`);

    // Si está en servicio, lo preparamos para Realtime Database
    if (c.enServicio && c.lat && c.lng) {
      colectivosActivosRTDB[uid] = {
        uid: uid,
        idVehiculo: c.patente,
        garitaId: GARITA_ID,
        latitud: c.lat,
        longitud: c.lng,
        estado: c.estado,
        ts: Date.now(),
      };
    }
  }

  // 6. Telemetría en Realtime Database
  console.log('\n--- 6. Inyectando Telemetría Activa en Realtime Database ---');
  await setRtdbData(token, 'colectivos_activos', colectivosActivosRTDB);
  console.log(`✅ ${Object.keys(colectivosActivosRTDB).length} colectivos activos inyectados en Realtime Database.`);

  console.log('\n======================================================');
  console.log('🎉 ¡Siembra completada con éxito!');
  console.log(`- Garita: ${GARITA_ID}`);
  console.log('- Paraderos: 8 nuevos (total ~20)');
  console.log('- Recorridos: 7 líneas completas');
  console.log('- Choferes: 7 cuentas listas (contraseña: la de TEST_DRIVER_PASSWORD)');
  console.log('- Telemetría: 3 colectivos activos transmitiendo');
  console.log('======================================================\n');
}

main().catch((err) => {
  console.error('❌ Error fatal en siembra:', err);
  process.exit(1);
});
