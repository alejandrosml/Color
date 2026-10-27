// Color for Android: the identifier of Color on Google Play, and the core in
// Rust beside the Flutter interface, one library per processor, built by
// scripts/android/construire-le-coeur.sh into src/main/jniLibs.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key of Google Play stays on the Mac of the author, outside the
// sources and outside every copy of work: the variable COLOR_UPLOAD_KEY,
// which the launcher of Google Play sets, names its key.properties, where it
// is; android/key.properties does the same for a build by hand. Without
// either, a release is signed with the debug key, good for trying, refused by
// Google Play.
val uploadKey = Properties().apply {
    val named = providers.environmentVariable("COLOR_UPLOAD_KEY").orNull
    val source = if (named.isNullOrEmpty()) rootProject.file("key.properties") else file(named)
    if (source.exists()) source.inputStream().use { load(it) }
}

android {
    namespace = "fr.aisml.color"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "fr.aisml.color"
        // Android 8: the sounds of the core play through AAudio.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (uploadKey.isNotEmpty()) {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (uploadKey.isNotEmpty()) {
                signingConfigs.getByName("upload")
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
