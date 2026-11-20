// scripts/seed_dummy_data.js
// Poblamiento de datos de prueba para ColeTotal (Quilpué).
//
// Los códigos de garita y la contraseña de los choferes de prueba ya no están
// escritos en el repositorio: los códigos dan acceso real (el de administrador
// permite gestionar la garita entera) y el repositorio se comparte.
//
// Uso:
//   CHOFER_CODE=... ADMIN_CODE=... TEST_DRIVER_PASSWORD=...
//   node scripts/seed_dummy_data.js
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

// Actualiza `colectivos_activos` mediante PATCH para no sobrescribir otras
// unidades que se encuentren transmitiendo en paralelo.
async function setRtdbData(token, path, data) {
  const url = `https://${PROJECT_ID}-default-rtdb.firebaseio.com/${path}.json`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
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

  // Paraderos y recorridos ya no se siembran: los colectivos no tienen
  // paraderos, y las líneas (ida y vuelta) las dibuja la garita en el editor
  // de la app. Los que sembraba este script eran inventados.

  // 3. Cuentas de Chofer (7 choferes)
  console.log('\n--- 3. Configurando 7 Cuentas de Chofer en Firebase Auth + Firestore ---');
  const choferes = [
    {
      patente: 'IBBI12',
      nombre: 'Matías Fuentes',
      activo: true,
      enServicio: true,
      lat: -33.0595,
      lng: -71.4552,
    },
    {
      patente: 'JHTB45',
      nombre: 'Carlos Soto Muñoz',
      activo: true,
      enServicio: true,
      lat: -33.0470,
      lng: -71.4420,
    },
    {
      patente: 'KPVD82',
      nombre: 'Manuel Riquelme Peña',
      activo: true,
      enServicio: true,
      lat: -33.0450,
      lng: -71.4405,
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
      activo: false,
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

    // Si está en servicio, lo preparamos para Realtime Database cumpliendo database.rules.json
    if (c.enServicio && c.lat && c.lng) {
      colectivosActivosRTDB[uid] = {
        uid: uid,
        idVehiculo: c.patente,
        garitaId: GARITA_ID,
        latitud: c.lat,
        longitud: c.lng,
        conectado: true,
        ts: Date.now(),
      };
    }
  }

  // 4. Telemetría en Realtime Database
  console.log('\n--- 4. Inyectando Telemetría Activa en Realtime Database ---');
  await setRtdbData(token, 'colectivos_activos', colectivosActivosRTDB);
  console.log(`✅ ${Object.keys(colectivosActivosRTDB).length} colectivos activos inyectados en Realtime Database.`);

  console.log('\n======================================================');
  console.log('🎉 ¡Siembra completada con éxito!');
  console.log(`- Garita: ${GARITA_ID}`);
  console.log('- Códigos de acceso: 2 (colectivero y administrador)');
  console.log('- Choferes: 7 cuentas listas (contraseña: la de TEST_DRIVER_PASSWORD)');
  console.log('- Telemetría: 3 colectivos activos transmitiendo');
  console.log('======================================================\n');
}

main().catch((err) => {
  console.error('❌ Error fatal en siembra:', err);
  process.exit(1);
});
