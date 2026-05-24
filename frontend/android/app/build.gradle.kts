plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging — applied only if `google-services.json` is present.
    // This lets the project build (and APKs be installed) before Firebase has been
    // configured. Drop the file from Firebase Console into android/app/ and the
    // plugin activates automatically on next build.
    id("com.google.gms.google-services") apply false
}

// Conditionally apply the Google Services plugin only when its config exists.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    println("✅ google-services.json detected — Firebase Cloud Messaging enabled.")
} else {
    println("⚠️  google-services.json not found in android/app/ — building without Firebase. Drop the file in and rebuild to enable push notifications.")
}

android {
    namespace = "com.fyp.fyp_frontend"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs that
        // need to be backported via desugar_jdk_libs for older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.fyp.fyp_frontend"
        // firebase_messaging requires minSdk >= 21. flutter_local_notifications
        // 17.x recommends 23+; pin here to avoid ambiguity from flutter.minSdkVersion.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Signed with the debug keys for now so `flutter build apk --release`
            // works on developer machines. Replace with a real keystore before
            // publishing to the Play Store.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring (Java 8 APIs on older Android).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
