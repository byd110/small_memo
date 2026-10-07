import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional private signing identity for builds you intend to keep updating.
// This file and all keystores are excluded from Git.
val personalKeyFile = rootProject.file("key.properties")
val personalKey = Properties()
if (personalKeyFile.exists()) {
    personalKeyFile.inputStream().use { personalKey.load(it) }
}

android {
    namespace = "dev.smallmemo.small_memo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.smallmemo.small_memo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // Android 7.0; the minimum supported by this Flutter toolchain.
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (personalKeyFile.exists()) {
            create("personal") {
                storeFile = file(personalKey.getProperty("storeFile"))
                storePassword = personalKey.getProperty("storePassword")
                keyAlias = personalKey.getProperty("keyAlias")
                keyPassword = personalKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without a private key this is a personal/test build, not a store release.
            // CI uses its temporary debug key; do not rely on that key for updates.
            signingConfig = signingConfigs.getByName(
                if (personalKeyFile.exists()) "personal" else "debug"
            )
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
