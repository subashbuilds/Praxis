plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

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
        versionCode = 4
        versionName = "2.1.0"
    }

    buildTypes {
        release {
            // No release keystore is committed; debug signing keeps CI builds
            // installable without exposing a private key in this repo.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
