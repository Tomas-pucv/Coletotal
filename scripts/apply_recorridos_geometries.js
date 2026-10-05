// scripts/apply_recorridos_geometries.js
// Calcula y guarda la geometría vial de cada recorrido en Firestore, siguiendo
// las calles (y sus sentidos de tránsito) entre los paraderos, en orden.
//
// Uso: node scripts/apply_recorridos_geometries.js
// Requiere haber hecho `firebase login` con una cuenta con acceso al proyecto.

const { getAccessToken, listCollection, patchDocument } = require('./lib/firebase_rest');

async function run() {
  console.log('🔄 Conectando con Firestore...');
  const token = await getAccessToken();

  // 1. Paraderos
  const paraderos = await listCollection(token, 'paraderos');
  const paraderosMap = new Map(paraderos.map((p) => [p.id, p]));
  console.log(`✅ ${paraderosMap.size} paraderos cargados.`);

  // 2. Recorridos
  //
  // Aquí había un parche puntual que reescribía los paraderos de un recorrido
  // concreto en cada ejecución, pisando lo que el administrador hubiera
  // editado desde la app. Ya cumplió su función y se quitó.
  const recorridos = await listCollection(token, 'recorridos');
  console.log(`✅ ${recorridos.length} recorridos encontrados en Firestore.\n`);

  let actualizados = 0;

  for (const r of recorridos) {
    const waypoints = (r.paraderoIds || [])
      .map((id) => paraderosMap.get(id))
      .filter((stop) => stop && typeof stop.lat === 'number' && typeof stop.lng === 'number');

    if (waypoints.length < 2) {
      console.warn(`⚠️ Omitiendo ${r.id}: tiene menos de 2 paraderos válidos.`);
      continue;
    }

    const coordsStr = waypoints.map((w) => `${w.lng},${w.lat}`).join(';');
    const osrmUrl = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=polyline6`;

    try {
      const osrmRes = await fetch(osrmUrl, {
        headers: { 'User-Agent': 'ColeTotal/1.0 (cl.coletotal.app)' },
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
      await patchDocument(
        token,
        `recorridos/${r.id}`,
        { geometria: route.geometry, actualizadoEn: new Date() },
        ['geometria', 'actualizadoEn'],
      );

      console.log(`📍 [${r.id}] ${r.nombre}`);
      console.log(
        `   Distancia: ${(route.distance / 1000).toFixed(2)} km | ` +
          `Tiempo estimado: ${(route.duration / 60).toFixed(1)} min | ` +
          `Geometría: ${route.geometry.length} chars`,
      );
      actualizados++;
    } catch (err) {
      console.error(`❌ Error en recorrido ${r.id}: ${err.message}`);
    }
  }

  console.log(`\n🎉 Geometrías guardadas: ${actualizados}/${recorridos.length}`);
}

run().catch((err) => {
  console.error('❌ Error:', err.message || err);
  process.exit(1);
});
