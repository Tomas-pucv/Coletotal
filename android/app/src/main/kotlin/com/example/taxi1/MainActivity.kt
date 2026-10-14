package com.example.taxi1

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
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

    /**
     * Lo que el turno necesita para seguir transmitiendo con la pantalla
     * bloqueada o en otra app (ver `lib/services/segundo_plano.dart`): que se
     * vea la notificación del servicio del GPS y quedar fuera del ahorro de
     * batería. Los dos se piden con los diálogos del sistema; la respuesta
     * vuelve a Dart cuando el usuario los cierra.
     */
    private var pendienteNotificaciones: MethodChannel.Result? = null
    private var pendienteBateria: MethodChannel.Result? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.coletotal/segundo_plano")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "estado" -> result.success(
                        mapOf(
                            "notificaciones" to notificacionesPermitidas(),
                            "bateria" to sinAhorroDeBateria(),
                            "xiaomi" to esXiaomi(),
                        )
                    )
                    "pedirNotificaciones" -> pedirNotificaciones(result)
                    "pedirSinAhorroDeBateria" -> pedirSinAhorroDeBateria(result)
                    "abrirAjustes" -> {
                        abrirAjustesDeLaApp()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun notificacionesPermitidas(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: true
    }

    private fun pedirNotificaciones(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || notificacionesPermitidas()) {
            result.success(notificacionesPermitidas())
            return
        }
        pendienteNotificaciones?.success(false)
        pendienteNotificaciones = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PEDIR_NOTIFICACIONES)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PEDIR_NOTIFICACIONES) {
            pendienteNotificaciones?.success(notificacionesPermitidas())
            pendienteNotificaciones = null
        }
    }

    private fun sinAhorroDeBateria(): Boolean =
        getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(packageName)
            ?: true

    /**
     * El diálogo del sistema "¿Permitir que la app se ejecute siempre en segundo
     * plano?". Es para apps cuya función principal lo necesita, como transmitir
     * la posición del chofer durante su turno.
     */
    @SuppressLint("BatteryLife")
    private fun pedirSinAhorroDeBateria(result: MethodChannel.Result) {
        if (sinAhorroDeBateria()) {
            result.success(true)
            return
        }
        pendienteBateria?.success(false)
        pendienteBateria = result
        try {
            startActivityForResult(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
                PEDIR_BATERIA,
            )
        } catch (e: Exception) {
            pendienteBateria = null
            result.success(false)
        }
    }

    @Deprecated("Activity#onActivityResult; FlutterActivity no ofrece otra vía")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PEDIR_BATERIA) {
            pendienteBateria?.success(sinAhorroDeBateria())
            pendienteBateria = null
        }
    }

    /** MIUI y HyperOS cortan la red a las apps en segundo plano aunque tengan un
     *  servicio en primer plano, salvo que se las deje "Sin restricciones". */
    private fun esXiaomi(): Boolean =
        Build.MANUFACTURER.lowercase() in setOf("xiaomi", "redmi", "poco")

    /** La ficha de la app en los ajustes: en Xiaomi ahí están el ahorro de
     *  batería y el inicio automático. */
    private fun abrirAjustesDeLaApp() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
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

    private companion object {
        const val PEDIR_NOTIFICACIONES = 7301
        const val PEDIR_BATERIA = 7302
    }
}
