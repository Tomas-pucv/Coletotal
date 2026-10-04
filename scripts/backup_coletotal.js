// scripts/backup_coletotal.js
// Herramienta de Respaldo Local para ColeTotal (Firestore + Realtime Database)
// Genera volcados en formato estándar JSON y GeoJSON para neutralidad de proveedor.

const fs = require('fs');
const path = require('path');
const auth = require('C:/Users/marco/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');

const PROJECT_ID = 'coletotal-32735';

function fromFirestoreFields(fields) {
  const obj = {};
  for (const [k, v] of Object.entries(fields || {})) {
    if (v.stringValue !== undefined) obj[k] = v.stringValue;
    else if (v.booleanValue !== undefined) obj[k] = v.booleanValue;
    else if (v.integerValue !== undefined) obj[k] = parseInt(v.integerValue, 10);
    else if (v.doubleValue !== undefined) obj[k] = v.doubleValue;
    else if (v.timestampValue !== undefined) obj[k] = v.timestampValue;
    else if (v.arrayValue !== undefined) {
      obj[k] = (v.arrayValue.values || []).map((item) => {
        if (item.stringValue !== undefined) return item.stringValue;
        if (item.integerValue !== undefined) return parseInt(item.integerValue, 10);
        return item;
      });
    } else if (v.mapValue !== undefined) {
      obj[k] = fromFirestoreFields(v.mapValue.fields);
    }
  }
  return obj;
}

async function getAccessToken() {
  const account = auth.getGlobalDefaultAccount();
  const tokenObj = await auth.getAccessToken(
    account.tokens.refresh_token,
    account.tokens.scopes
  );
  return tokenObj.access_token;
}

async function fetchCollection(token, colName) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${colName}?pageSize=300`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`Error fetching ${colName}: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  const list = [];
  for (const doc of data.documents || []) {
    const id = doc.name.split(`/${colName}/`)[1];
    list.push({ id, ...fromFirestoreFields(doc.fields) });
  }
  return list;
}

async function fetchRtdb(token, nodePath) {
  const url = `https://${PROJECT_ID}-default-rtdb.firebaseio.com/${nodePath}.json?access_token=${token}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  return res.json();
}

function toGeoJsonParaderos(paraderos) {
  return {
    type: 'FeatureCollection',
    name: 'ColeTotal_Paraderos',
    features: paraderos
      .filter((p) => typeof p.lat === 'number' && typeof p.lng === 'number')
      .map((p) => ({
        type: 'Feature',
        properties: {
          id: p.id,
          nombre: p.nombre,
          direccion: p.direccion || '',
          garitaId: p.garitaId || '',
          activo: p.activo !== false,
        },
        geometry: {
          type: 'Point',
          coordinates: [p.lng, p.lat],
        },
      })),
  };
}

async function main() {
  console.log('📦 Iniciando proceso de respaldo local de ColeTotal...');
  const token = await getAccessToken();
  console.log('🔑 Autenticación validada.');

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = path.join(__dirname, '..', 'backups', `backup_${timestamp}`);
  fs.mkdirSync(backupDir, { recursive: true });

  const collections = ['garitas', 'codigos_acceso', 'usuarios', 'paraderos', 'recorridos'];
  const manifest = {
    timestamp: new Date().toISOString(),
    projectId: PROJECT_ID,
    collections: {},
    rtdb: {},
  };

  for (const col of collections) {
    process.stdout.write(`  ⏳ Descargando colección '${col}'... `);
    const docs = await fetchCollection(token, col);
    const filePath = path.join(backupDir, `${col}.json`);
    fs.writeFileSync(filePath, JSON.stringify(docs, null, 2), 'utf-8');
    manifest.collections[col] = docs.length;
    console.log(`✅ [${docs.length} documentos guardados]`);

    if (col === 'paraderos') {
      const geoJson = toGeoJsonParaderos(docs);
      fs.writeFileSync(
        path.join(backupDir, 'paraderos.geojson'),
        JSON.stringify(geoJson, null, 2),
        'utf-8'
      );
      console.log(`     🗺️ GeoJSON de paraderos generado: paraderos.geojson`);
    }
  }

  process.stdout.write(`  ⏳ Descargando telemetría activa de Realtime Database... `);
  const rtdbActivos = await fetchRtdb(token, 'colectivos_activos');
  fs.writeFileSync(
    path.join(backupDir, 'colectivos_activos.json'),
    JSON.stringify(rtdbActivos || {}, null, 2),
    'utf-8'
  );
  const rtdbCount = Object.keys(rtdbActivos || {}).length;
  manifest.rtdb['colectivos_activos'] = rtdbCount;
  console.log(`✅ [${rtdbCount} unidades activas respaldadas]`);

  fs.writeFileSync(
    path.join(backupDir, 'manifest.json'),
    JSON.stringify(manifest, null, 2),
    'utf-8'
  );

  console.log('\n======================================================');
  console.log('💾 ¡Respaldo completado exitosamente!');
  console.log(`📁 Directorio: ${backupDir}`);
  console.log('📄 Archivos generados:');
  console.log('   - garitas.json');
  console.log('   - codigos_acceso.json');
  console.log('   - usuarios.json');
  console.log('   - paraderos.json (+ paraderos.geojson)');
  console.log('   - recorridos.json');
  console.log('   - colectivos_activos.json');
  console.log('   - manifest.json');
  console.log('======================================================\n');
}

main().catch((err) => {
  console.error('❌ Error en proceso de respaldo:', err);
  process.exit(1);
});
