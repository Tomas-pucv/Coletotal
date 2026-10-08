package com.example.taxi1

import android.os.Handler
import android.os.Looper
import com.valhalla.valhalla.Valhalla
import com.valhalla.valhalla.ValhallaException
import com.valhalla.valhalla.config.ValhallaConfigFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    /**
     * Valhalla dentro del teléfono: calcula las rutas a pie y los trazados de las
     * líneas sin conexión, con los datos de ruteo que vienen en el APK
     * (`assets/map/ruteo_valparaiso.tar`, copiados por `BasemapService`).
     *
     * Las consultas son las mismas que se le mandan al servidor público
     * (`lib/services/valhalla_client.dart`) y la respuesta vuelve tal cual, en
     * JSON. Se atienden de a una, en un hilo aparte: Valhalla tarda unos
     * milisegundos por ruta y no puede bloquear la interfaz.
     */
    private val valhallaHilo = Executors.newSingleThreadExecutor()
    private var valhalla: Valhalla? = null
    private var valhallaTeselas: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val principal = Handler(Looper.getMainLooper())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.coletotal/valhalla")
            .setMethodCallHandler { call, result ->
                if (call.method != "route") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val teselas = call.argument<String>("tiles")
                val consulta = call.argument<String>("request")
                if (teselas == null || consulta == null) {
                    result.error("ARGUMENTOS", "Faltan tiles o request", null)
                    return@setMethodCallHandler
                }
                valhallaHilo.execute {
                    try {
                        val respuesta = motor(teselas).routeRaw(consulta)
                        principal.post { result.success(respuesta) }
                    } catch (e: ValhallaException) {
                        // Sin ruta entre esos puntos, o fuera de los datos de la
                        // región: la app le pregunta al servidor.
                        principal.post { result.error("SIN_RUTA", e.message, null) }
                    } catch (e: Exception) {
                        principal.post { result.error("VALHALLA", e.toString(), null) }
                    }
                }
            }
    }

    /** Un solo motor, que se rehace sólo si cambian los datos de ruteo. */
    private fun motor(teselas: String): Valhalla {
        val actual = valhalla
        if (actual != null && valhallaTeselas == teselas) return actual
        actual?.close()
        val nuevo = Valhalla(this, ValhallaConfigFactory.usingTileExtract(teselas))
        valhalla = nuevo
        valhallaTeselas = teselas
        return nuevo
    }

    override fun onDestroy() {
        valhallaHilo.execute {
            valhalla?.close()
            valhalla = null
        }
        valhallaHilo.shutdown()
        super.onDestroy()
    }
}
