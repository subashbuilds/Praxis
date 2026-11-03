plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.xapi.polydev"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.xapi.polydev"
        minSdk = 24
        targetSdk = 36
        versionCode = 13
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // The shipped XAPK is signed with the Play app-signing key,
            // which we do not have. Debug signing keeps the project buildable.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
