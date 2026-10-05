// scripts/lib/firebase_rest.js
// Utilidades compartidas por los scripts de administración de ColeTotal:
// credenciales de Firebase CLI y acceso a la REST API de Firestore.
//
// Antes cada script repetía este código y además hacía `require` de una ruta
// absoluta del computador de un integrante (C:/Users/marco/AppData/...), así
// que en cualquier otro equipo fallaban en la primera línea.

const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'coletotal-32735';
const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

/**
 * Carga el módulo de autenticación de firebase-tools.
 *
 * Busca primero en FIREBASE_TOOLS_PATH (carpeta de firebase-tools) y después
 * en la instalación global de npm.
 */
function loadFirebaseToolsAuth() {
  const candidates = [];
  if (process.env.FIREBASE_TOOLS_PATH) candidates.push(process.env.FIREBASE_TOOLS_PATH);
  try {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8' }).trim();
    candidates.push(path.join(globalRoot, 'firebase-tools'));
  } catch (_) {
    // npm no está en el PATH: sólo queda FIREBASE_TOOLS_PATH.
  }

  for (const base of candidates) {
    try {
      return require(path.join(base, 'lib', 'auth'));
    } catch (_) {
      // Se prueba el siguiente candidato.
    }
  }
  throw new Error(
    'No se encontró firebase-tools. Instálalo con `npm install -g firebase-tools` ' +
      'y ejecuta `firebase login`, o define FIREBASE_TOOLS_PATH con la carpeta de firebase-tools.',
  );
}

/** Token de acceso de la cuenta con la que se hizo `firebase login`. */
async function getAccessToken() {
  const auth = loadFirebaseToolsAuth();
  const account = auth.getGlobalDefaultAccount();
  if (!account) {
    throw new Error('No hay una sesión de Firebase CLI: ejecuta `firebase login`.');
  }
  const tokenObj = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes);
  return tokenObj.access_token;
}

/** Valor obligatorio de una variable de entorno; corta el script si falta. */
function requireEnv(name, hint) {
  const value = process.env[name];
  if (!value) {
    console.error(`❌ Falta la variable de entorno ${name}.${hint ? ' ' + hint : ''}`);
    process.exit(1);
  }
  return value;
}

function toFirestoreValue(v) {
  if (v === null || v === undefined) return null;
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: v.toString() } : { doubleValue: v };
  }
  if (Array.isArray(v)) {
    return { arrayValue: { values: v.map(toFirestoreValue).filter((x) => x !== null) } };
  }
  if (typeof v === 'object') return { mapValue: { fields: toFirestoreFields(v) } };
  return null;
}

/** Objeto plano de JavaScript → `fields` de la REST API de Firestore. */
function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    const value = toFirestoreValue(v);
    if (value !== null) fields[k] = value;
  }
  return fields;
}

function fromFirestoreValue(v) {
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.integerValue !== undefined) return parseInt(v.integerValue, 10);
  if (v.doubleValue !== undefined) return v.doubleValue;
  if (v.timestampValue !== undefined) return v.timestampValue;
  if (v.nullValue !== undefined) return null;
  if (v.arrayValue !== undefined) return (v.arrayValue.values || []).map(fromFirestoreValue);
  if (v.mapValue !== undefined) return fromFirestoreFields(v.mapValue.fields);
  return v;
}

/** `fields` de la REST API de Firestore → objeto plano de JavaScript. */
function fromFirestoreFields(fields) {
  const obj = {};
  for (const [k, v] of Object.entries(fields || {})) obj[k] = fromFirestoreValue(v);
  return obj;
}

/**
 * Todos los documentos de una colección (o subcolección), página por página.
 *
 * Antes se pedía una sola página de 100 o 300 documentos y el resto se perdía
 * en silencio.
 */
async function listCollection(token, collectionPath) {
  const docs = [];
  let pageToken;
  do {
    const url = new URL(`${FIRESTORE_BASE}/${collectionPath}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) {
      throw new Error(`Error leyendo ${collectionPath}: ${res.status} ${await res.text()}`);
    }
    const data = await res.json();
    for (const doc of data.documents || []) {
      docs.push({ id: doc.name.split('/').pop(), ...fromFirestoreFields(doc.fields) });
    }
    pageToken = data.nextPageToken;
  } while (pageToken);
  return docs;
}

/**
 * Escribe un documento. Con `updateMask` sólo toca esos campos; sin él,
 * reemplaza el documento entero.
 */
async function patchDocument(token, docPath, data, updateMask) {
  const url = new URL(`${FIRESTORE_BASE}/${docPath}`);
  for (const field of updateMask || []) url.searchParams.append('updateMask.fieldPaths', field);
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: toFirestoreFields(data) }),
  });
  if (!res.ok) {
    throw new Error(`Error escribiendo ${docPath}: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

module.exports = {
  PROJECT_ID,
  getAccessToken,
  requireEnv,
  toFirestoreFields,
  fromFirestoreFields,
  listCollection,
  patchDocument,
};
