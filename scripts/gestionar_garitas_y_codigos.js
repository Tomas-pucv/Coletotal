// scripts/gestionar_garitas_y_codigos.js
// Herramienta CLI para gestionar Garitas y Códigos de Acceso en Firestore.
//
// Comandos disponibles:
//   1. Listar garitas y códigos actuales:
//      node scripts/gestionar_garitas_y_codigos.js listar
//
//   2. Crear/actualizar una nueva garita junto con sus códigos iniciales:
//      node scripts/gestionar_garitas_y_codigos.js nueva-garita <garitaId> "<Nombre>" "<Comuna>" <CODIGO_CONDUCTOR> <CODIGO_ADMIN>
//      Ejemplo:
//      node scripts/gestionar_garitas_y_codigos.js nueva-garita garita_quilpue_02 "Línea 2 Quilpué" "Quilpué" CONDUCTORLINEA2 ADMINLINEA2
//
//   3. Crear o actualizar un código de acceso para una garita:
//      node scripts/gestionar_garitas_y_codigos.js crear-codigo <CODIGO> <garitaId> <conductor|administrador>
//
//   4. Activar o desactivar un código existente:
//      node scripts/gestionar_garitas_y_codigos.js estado-codigo <CODIGO> <on|off>
//
//   5. Eliminar un código de acceso:
//      node scripts/gestionar_garitas_y_codigos.js borrar-codigo <CODIGO>

const {
  PROJECT_ID,
  getAccessToken,
  listCollection,
  patchDocument,
} = require('./lib/firebase_rest');

const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function deleteDocument(token, docPath) {
  const res = await fetch(`${FIRESTORE_BASE}/${docPath}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`Error eliminando ${docPath}: ${res.status} ${await res.text()}`);
  }
}

function normalizarRol(input) {
  const v = (input || '').trim().toLowerCase();
  if (v === 'conductor' || v === 'colectivero') return 'colectivero';
  if (v === 'admin' || v === 'administrador') return 'administrador';
  throw new Error(`Rol inválido "${input}". Usa "conductor" o "administrador".`);
}

function validarCodigoSinChofer(codigo) {
  const c = (codigo || '').trim().toUpperCase();
  if (c.length < 4 || c.length > 40) {
    throw new Error('El código debe tener entre 4 y 40 caracteres.');
  }
  if (c.includes('CHOFER')) {
    throw new Error('El término "CHOFER" no está permitido en los códigos. Usa "CONDUCTOR".');
  }
  return c;
}

async function cmdListar(token) {
  const garitas = await listCollection(token, 'garitas');
  const codigos = await listCollection(token, 'codigos_acceso');

  console.log('\n🏢 GARITAS REGISTRADAS:');
  for (const g of garitas) {
    console.log(`  • [${g.id}] ${g.nombre} (${g.comuna || 'Sin comuna'})`);
  }

  console.log('\n🔑 CÓDIGOS DE ACCESO:');
  for (const c of codigos) {
    const rolLabel = c.rol === 'administrador' ? 'Administrador' : 'Conductor (colectivero)';
    const estado = c.activo ? '✅ ACTIVO' : '⛔ INACTIVO';
    console.log(`  • ${c.id.padEnd(20)} | ${estado} | Rol: ${rolLabel.padEnd(23)} | Garita: ${c.garitaId}`);
  }
  console.log('');
}

async function main() {
  const [, , cmd, ...args] = process.argv;
  const token = await getAccessToken();

  switch (cmd) {
    case 'listar': {
      await cmdListar(token);
      break;
    }

    case 'nueva-garita': {
      const [garitaId, nombre, comuna, codConductor, codAdmin] = args;
      if (!garitaId || !nombre || !comuna || !codConductor || !codAdmin) {
        console.error(
          'Uso: node scripts/gestionar_garitas_y_codigos.js nueva-garita <garitaId> "<Nombre>" "<Comuna>" <CODIGO_CONDUCTOR> <CODIGO_ADMIN>',
        );
        process.exit(1);
      }
      const cCond = validarCodigoSinChofer(codConductor);
      const cAdm = validarCodigoSinChofer(codAdmin);

      await patchDocument(token, `garitas/${garitaId}`, {
        nombre,
        comuna,
      });
      await patchDocument(token, `codigos_acceso/${cCond}`, {
        garitaId,
        rol: 'colectivero',
        activo: true,
      });
      await patchDocument(token, `codigos_acceso/${cAdm}`, {
        garitaId,
        rol: 'administrador',
        activo: true,
      });
      console.log(`✅ Garita "${nombre}" (${garitaId}) creada con códigos:`);
      console.log(`   - Conductor:     ${cCond}`);
      console.log(`   - Administrador: ${cAdm}`);
      break;
    }

    case 'crear-codigo': {
      const [codigoRaw, garitaId, rolRaw] = args;
      if (!codigoRaw || !garitaId || !rolRaw) {
        console.error(
          'Uso: node scripts/gestionar_garitas_y_codigos.js crear-codigo <CODIGO> <garitaId> <conductor|administrador>',
        );
        process.exit(1);
      }
      const codigo = validarCodigoSinChofer(codigoRaw);
      const rol = normalizarRol(rolRaw);
      await patchDocument(token, `codigos_acceso/${codigo}`, {
        garitaId,
        rol,
        activo: true,
      });
      console.log(`✅ Código ${codigo} (${rol === 'administrador' ? 'Administrador' : 'Conductor'}) activo para ${garitaId}.`);
      break;
    }

    case 'estado-codigo': {
      const [codigoRaw, estadoRaw] = args;
      if (!codigoRaw || !['on', 'off'].includes((estadoRaw || '').toLowerCase())) {
        console.error(
          'Uso: node scripts/gestionar_garitas_y_codigos.js estado-codigo <CODIGO> <on|off>',
        );
        process.exit(1);
      }
      const codigo = codigoRaw.trim().toUpperCase();
      const activo = estadoRaw.toLowerCase() === 'on';
      await patchDocument(token, `codigos_acceso/${codigo}`, { activo }, ['activo']);
      console.log(`✅ Código ${codigo} ahora está ${activo ? 'ACTIVO' : 'INACTIVO'}.`);
      break;
    }

    case 'borrar-codigo': {
      const [codigoRaw] = args;
      if (!codigoRaw) {
        console.error('Uso: node scripts/gestionar_garitas_y_codigos.js borrar-codigo <CODIGO>');
        process.exit(1);
      }
      const codigo = codigoRaw.trim().toUpperCase();
      await deleteDocument(token, `codigos_acceso/${codigo}`);
      console.log(`🗑️ Código ${codigo} eliminado de Firestore.`);
      break;
    }

    default: {
      await cmdListar(token);
      break;
    }
  }
}

main().catch((err) => {
  console.error('❌ Error:', err.message || err);
  process.exit(1);
});
