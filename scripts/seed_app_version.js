// scripts/seed_app_version.js
// Publica en Firestore (config/app_version) la versión que la app ofrece
// actualizar.
//
// La versión se lee de `pubspec.yaml`: la app instalada compara su número de
// compilación (lo que va después del "+") contra `versionCode`, así que ambos
// tienen que salir del mismo lugar. Antes había que editar este archivo a
// mano en cada entrega.
//
// Uso:
//   APK_URL=https://.../ColeTotal.apk \
//   CHANGELOG="• Corrección del GPS en segundo plano" \
//   node scripts/seed_app_version.js
//
// Opcionales: MIN_REQUIRED (número de compilación mínimo que puede seguir
// operando; las anteriores ven la actualización como obligatoria),
// MANDATORY=1, VERSION_NAME y VERSION_CODE (para no usar los del pubspec).

const fs = require('fs');
const path = require('path');
const { getAccessToken, patchDocument, requireEnv } = require('./lib/firebase_rest');

function versionFromPubspec() {
  const pubspec = fs.readFileSync(path.join(__dirname, '..', 'pubspec.yaml'), 'utf8');
  const match = pubspec.match(/^version:\s*([0-9A-Za-z.\-]+)\+(\d+)\s*$/m);
  if (!match) throw new Error('No se encontró `version: x.y.z+n` en pubspec.yaml');
  return { name: match[1], code: parseInt(match[2], 10) };
}

async function main() {
  const pubspec = versionFromPubspec();
  const apkUrl = requireEnv('APK_URL', 'Debe ser la URL https directa del APK.');
  if (!apkUrl.startsWith('https://')) {
    console.error('❌ APK_URL debe empezar con https:// (la app rechaza otros enlaces).');
    process.exit(1);
  }

  const versionData = {
    versionCode: process.env.VERSION_CODE ? parseInt(process.env.VERSION_CODE, 10) : pubspec.code,
    versionName: process.env.VERSION_NAME || pubspec.name,
    minRequiredVersionCode: process.env.MIN_REQUIRED ? parseInt(process.env.MIN_REQUIRED, 10) : 1,
    apkUrl,
    changelog: process.env.CHANGELOG || '',
    esObligatoria: process.env.MANDATORY === '1',
  };

  console.log('🔄 Actualizando config/app_version en Firestore...');
  const token = await getAccessToken();
  await patchDocument(token, 'config/app_version', versionData);
  console.log('✅ config/app_version establecido:');
  console.log(JSON.stringify(versionData, null, 2));
}

main().catch((err) => {
  console.error('❌ Error:', err.message || err);
  process.exit(1);
});
