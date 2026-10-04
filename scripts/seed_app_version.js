// scripts/seed_app_version.js
// Configura o actualiza el documento config/app_version en Cloud Firestore

const auth = require('C:/Users/marco/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');

const PROJECT_ID = 'coletotal-32735';

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
    }
  }
  return fields;
}

async function getAccessToken() {
  const account = auth.getGlobalDefaultAccount();
  const tokenObj = await auth.getAccessToken(
    account.tokens.refresh_token,
    account.tokens.scopes
  );
  return tokenObj.access_token;
}

async function setFirestoreDoc(token, collection, docId, data) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collection}/${docId}`;
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
    throw new Error(`Error setFirestoreDoc [${collection}/${docId}]: ${res.status} ${errText}`);
  }
  return res.json();
}

async function main() {
  console.log('🔄 Actualizando documento config/app_version en Firestore...');
  const token = await getAccessToken();

  // Versión actual base: 0.4.3+3 (código 3).
  // Se deja configurado en 3 para que no moleste a los usuarios actuales,
  // y se documenta cómo subir a 4 para activar el pop-up de actualización a todos los choferes.
  const versionData = {
    versionCode: 4,
    versionName: '0.4.3.1',
    minRequiredVersionCode: 3,
    apkUrl: 'https://files.catbox.moe/99fybl.apk',
    changelog: '• Nueva apariencia visual: Amarillo cálido anaranjado (estética de colectivo chileno).\n• Sistema de auditoría y diagnóstico de turnos por lotes.\n• Mapeo y navegación multi-garita para Transportes Serrano.\n• Búsqueda rápida de hitos urbanos (Líder, Hospital, Plazas).',
    esObligatoria: false,
  };

  await setFirestoreDoc(token, 'config', 'app_version', versionData);
  console.log('✅ Documento config/app_version establecido correctamente:');
  console.log(JSON.stringify(versionData, null, 2));
}

main().catch((err) => {
  console.error('❌ Error:', err);
  process.exit(1);
});
