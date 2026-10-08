import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de las versiones de release.
//
// Las actualizaciones OTA instalan un APK encima del anterior, y Android sólo
// lo acepta si ambos están firmados con la MISMA llave. Firmar con la llave de
// debug (que es distinta en cada computador) hacía que un APK compilado por un
// integrante no pudiera actualizar uno compilado por el otro.
//
// Con `android/key.properties` (fuera de git, ver README) se usa la llave del
// proyecto; sin él se sigue firmando con la de debug, como hasta ahora.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.taxi1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.taxi1"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    packaging {
        jniLibs {
            // valhalla-mobile trae también x86 de 32 bits, una arquitectura
            // para la que Flutter no compila: serían 2,6 MB de más en el APK.
            excludes += "lib/x86/**"
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Valhalla dentro del teléfono: rutas a pie y trazados de las líneas sin
    // conexión (ver MainActivity.kt). La 0.6.4 trae Valhalla 3.9.1, la misma
    // versión con que scripts/mapa_base/ruteo.py arma los datos de ruteo: un
    // motor más viejo podría no leerlos.
    implementation("io.github.rallista:valhalla-mobile:0.6.4")
    // Trae `ValhallaConfig`, que MainActivity arma; valhalla-mobile lo usa
    // pero no lo expone para compilar. La versión es la que pide la 0.6.4.
    implementation("io.github.rallista:valhalla-models-config:0.6.0")
}
