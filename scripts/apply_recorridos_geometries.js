// scripts/apply_recorridos_geometries.js
// Calcula y guarda la geometría vial precisa de cada recorrido en Firestore
// respetando las calles y sentidos de tránsito de Quilpué.

const auth = require('C:/Users/marco/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');

const PROJECT_ID = 'coletotal-32735';

async function getAccessToken() {
  const account = auth.getGlobalDefaultAccount();
  const tokenObj = await auth.getAccessToken(
    account.tokens.refresh_token,
    account.tokens.scopes
  );
  return tokenObj.access_token;
}

function parseFirestoreFields(fields) {
  const result = {};
  if (!fields) return result;
  for (const [key, value] of Object.entries(fields)) {
    if (value.stringValue !== undefined) result[key] = value.stringValue;
    else if (value.integerValue !== undefined) result[key] = parseInt(value.integerValue, 10);
    else if (value.doubleValue !== undefined) result[key] = value.doubleValue;
    else if (value.booleanValue !== undefined) result[key] = value.booleanValue;
    else if (value.arrayValue !== undefined) {
      result[key] = (value.arrayValue.values || []).map(v => v.stringValue || v.integerValue || v.doubleValue);
    }
  }
  return result;
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === undefined) continue;
    if (typeof v === 'string') {
      fields[k] = { stringValue: v };
    } else if (typeof v === 'boolean') {
      fields[k] = { booleanValue: v };
    } else if (typeof v === 'number') {
      if (Number.isInteger(v)) {
        fields[k] = { integerValue: v.toString() };
      } else {
        fields[k] = { doubleValue: v };
      }
    } else if (Array.isArray(v)) {
      fields[k] = {
        arrayValue: {
          values: v.map((item) => ({ stringValue: String(item) })),
        },
      };
    }
  }
  return fields;
}

async function updateFirestoreDoc(token, collection, docId, data, updateMaskFields) {
  let url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collection}/${docId}`;
  if (updateMaskFields && updateMaskFields.length > 0) {
    const maskParams = updateMaskFields.map(f => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&');
    url += `?${maskParams}`;
  }
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: toFirestoreFields(data) }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Error updating doc [${collection}/${docId}]: ${res.status} ${errText}`);
  }
  return res.json();
}

async function run() {
  console.log('🔄 Conectando con Firestore...');
  const token = await getAccessToken();

  // 1. Cargar paraderos
  const paraderosRes = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/paraderos?pageSize=100`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  const paraderosData = await paraderosRes.json();
  const paraderosMap = new Map();
  for (const doc of (paraderosData.documents || [])) {
    const id = doc.name.split('/').pop();
    const data = parseFirestoreFields(doc.fields);
    paraderosMap.set(id, { id, ...data });
  }
  console.log(`✅ ${paraderosMap.size} paraderos cargados.`);

  // 2. Corregir IDs de paraderos antiguos en LA9lCeZPZ2Gv66LuO8Jy si existen
  // (seed-estacion-quilpue -> Awwtn1GKE6TXwQiMH9IB, seed-hospital-quilpue -> qndlGOHDC8XX4xh96QT7)
  const legacyRecorridoId = 'LA9lCeZPZ2Gv66LuO8Jy';
  try {
    await updateFirestoreDoc(
      token,
      'recorridos',
      legacyRecorridoId,
      {
        paraderoIds: [
          'Awwtn1GKE6TXwQiMH9IB', // Estación Quilpué
          'qndlGOHDC8XX4xh96QT7', // Hospital Quilpué
          'I0jjhDLOVQEytVeW9NRJ', // Belloto
          'HP64aCEKE62hH3oFh79L', // Claudio Arrau
        ]
      },
      ['paraderoIds']
    );
    console.log(`✅ Actualizados paraderoIds para recorrido legado ${legacyRecorridoId}`);
  } catch (e) {
    console.log(`ℹ️ Nota sobre legado: ${e.message}`);
  }

  // 3. Cargar todos los recorridos actualizados
  const recorridosRes = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/recorridos?pageSize=100`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  const recorridosData = await recorridosRes.json();
  const recorridos = (recorridosData.documents || []).map(doc => {
    const id = doc.name.split('/').pop();
    return { id, ...parseFirestoreFields(doc.fields) };
  });
  console.log(`✅ ${recorridos.length} recorridos encontrados en Firestore.\n`);

  let actualizados = 0;

  for (const r of recorridos) {
    const stopIds = r.paraderoIds || [];
    const waypoints = [];

    for (const stopId of stopIds) {
      const stop = paraderosMap.get(stopId);
      if (stop && stop.lat && stop.lng) {
        waypoints.push({ id: stopId, name: stop.nombre, lat: stop.lat, lng: stop.lng });
      }
    }

    if (waypoints.length < 2) {
      console.warn(`⚠️ Omitiendo ${r.id}: tiene menos de 2 paraderos válidos.`);
      continue;
    }

    const coordsStr = waypoints.map(w => `${w.lng},${w.lat}`).join(';');
    const osrmUrl = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=polyline6&steps=true`;

    try {
      const osrmRes = await fetch(osrmUrl, {
        headers: { 'User-Agent': 'ColeTotal/1.0 (coletotal.app)' }
      });
      if (!osrmRes.ok) {
        console.error(`❌ OSRM status ${osrmRes.status} para ${r.id}`);
        continue;
      }
      const osrmJson = await osrmRes.json();
      if (osrmJson.code !== 'Ok' || !osrmJson.routes || !osrmJson.routes[0]) {
        console.error(`❌ OSRM no encontró ruta para ${r.id}: ${osrmJson.code}`);
        continue;
      }

      const route = osrmJson.routes[0];
      const encodedGeometry = route.geometry;
      const distKm = (route.distance / 1000).toFixed(2);
      const durMin = (route.duration / 60).toFixed(1);

      // Guardar en Firestore doc de este recorrido
      await updateFirestoreDoc(
        token,
        'recorridos',
        r.id,
        {
          geometria: encodedGeometry,
          actualizadoEn: new Date().toISOString(),
        },
        ['geometria', 'actualizadoEn']
      );

      console.log(`📍 [${r.id}] ${r.nombre}`);
      console.log(`   Distancia: ${distKm} km | Tiempo estimado: ${durMin} min | Geometría: ${encodedGeometry.length} chars`);
      actualizados++;
    } catch (err) {
      console.error(`❌ Error en recorrido ${r.id}: ${err.message}`);
    }
  }

  console.log(`\n🎉 Geometrías viales precomputadas y guardadas exitosamente: ${actualizados}/${recorridos.length}`);
}

run().catch(console.error);
