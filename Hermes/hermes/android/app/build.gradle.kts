plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mobstudios.hermes"
    compileSdk = flutter.compileSdkVersion
    // whisper_ggml NDK 29 istiyor; en yüksek sürümü pinliyoruz (geri uyumlu).
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mobstudios.hermes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // vosk_flutter_2 (Türkçe ASR de-risk) minSdk 30 istiyor (Android 11+).
        // Geçici: Vosk değerlendirmesi için yükseltildi. Vosk benimsenmezse
        // flutter.minSdkVersion'a geri dön (eski cihaz desteği için).
        minSdk = maxOf(flutter.minSdkVersion, 30)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
