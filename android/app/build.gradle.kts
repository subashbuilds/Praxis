plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystore = System.getenv("KEYSTORE_PATH")?.takeIf { it.trim().isNotEmpty() }
val releaseStorePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
val releaseKeyAlias = System.getenv("KEY_ALIAS") ?: ""
val releaseKeyPassword = System.getenv("KEY_PASSWORD")
    ?.takeIf { it.isNotEmpty() } ?: releaseStorePassword

android {
    namespace = "com.subash.praxis"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.subash.praxis"
        minSdk = 24
        targetSdk = 36
        versionCode = 5
        versionName = "2.2.0"
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    // Debug and release builds share the environment keystore when it is
    // available, so local debug installs and signed builds use one identity.
    // Without the environment, both fall back to the standard debug key so the
    // project still builds.
    val commonSigningConfig = if (releaseKeystore != null) {
        signingConfigs.getByName("release")
    } else {
        signingConfigs.getByName("debug")
    }

    buildTypes {
        debug {
            signingConfig = commonSigningConfig
        }
        release {
            signingConfig = commonSigningConfig
        }
    }
}

flutter {
    source = "../.."
}
