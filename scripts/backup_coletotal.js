// scripts/backup_coletotal.js
// Herramienta de Respaldo Local para ColeTotal (Firestore + Realtime Database)
// Genera volcados en formato estándar JSON y GeoJSON para neutralidad de proveedor.
//
// Uso: node scripts/backup_coletotal.js
// Los respaldos quedan en backups/ (ignorado por git: contiene datos personales
// de los choferes).

const fs = require('fs');
const path = require('path');
const { PROJECT_ID, getAccessToken, listCollection } = require('./lib/firebase_rest');

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

function write(dir, file, data) {
  fs.writeFileSync(path.join(dir, file), JSON.stringify(data, null, 2), 'utf-8');
}

async function main() {
  console.log('📦 Iniciando proceso de respaldo local de ColeTotal...');
  const token = await getAccessToken();
  console.log('🔑 Autenticación validada.');

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = path.join(__dirname, '..', 'backups', `backup_${timestamp}`);
  fs.mkdirSync(backupDir, { recursive: true });

  // `config` guarda la versión publicada para la actualización OTA.
  const collections = ['garitas', 'codigos_acceso', 'usuarios', 'paraderos', 'recorridos', 'config'];
  const manifest = {
    timestamp: new Date().toISOString(),
    projectId: PROJECT_ID,
    collections: {},
    rtdb: {},
  };

  let garitas = [];
  for (const col of collections) {
    process.stdout.write(`  ⏳ Descargando colección '${col}'... `);
    const docs = await listCollection(token, col);
    write(backupDir, `${col}.json`, docs);
    manifest.collections[col] = docs.length;
    console.log(`✅ [${docs.length} documentos]`);

    if (col === 'garitas') garitas = docs;
    if (col === 'paraderos') {
      write(backupDir, 'paraderos.geojson', toGeoJsonParaderos(docs));
      console.log('     🗺️ GeoJSON de paraderos generado: paraderos.geojson');
    }
  }

  // La auditoría de turnos es una subcolección de cada garita.
  const auditoria = {};
  let totalAuditoria = 0;
  for (const g of garitas) {
    const docs = await listCollection(token, `garitas/${g.id}/auditoria_turnos`);
    auditoria[g.id] = docs;
    totalAuditoria += docs.length;
  }
  write(backupDir, 'auditoria_turnos.json', auditoria);
  manifest.collections['garitas/*/auditoria_turnos'] = totalAuditoria;
  console.log(`  ✅ Auditoría de turnos: ${totalAuditoria} turnos`);

  process.stdout.write('  ⏳ Descargando telemetría activa de Realtime Database... ');
  const rtdbActivos = await fetchRtdb(token, 'colectivos_activos');
  write(backupDir, 'colectivos_activos.json', rtdbActivos || {});
  const rtdbCount = Object.keys(rtdbActivos || {}).length;
  manifest.rtdb['colectivos_activos'] = rtdbCount;
  console.log(`✅ [${rtdbCount} unidades]`);

  write(backupDir, 'manifest.json', manifest);

  console.log('\n======================================================');
  console.log('💾 ¡Respaldo completado exitosamente!');
  console.log(`📁 Directorio: ${backupDir}`);
  console.log('======================================================\n');
}

main().catch((err) => {
  console.error('❌ Error en proceso de respaldo:', err.message || err);
  process.exit(1);
});
