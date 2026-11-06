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

    buildTypes {
        release {
            // A local or CI run without the signing environment falls back to
            // the debug key so the project still builds. The manual release
            // workflow injects the real keystore from repository secrets.
            signingConfig = if (releaseKeystore != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
