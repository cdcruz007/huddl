// ✅ CRITICAL: Required imports for signing configuration
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load signing properties from key.properties (lives in android/ = rootProject dir)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.huddlconnect.connect"
    // S20 fix: pin compileSdk to 35 explicitly — flutter.compileSdkVersion can
    // resolve to an older value when the Flutter SDK version is changed, which
    // would cause a build failure if any dependency requires API 35 features.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
	isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String? ?: "huddl"
            keyPassword = keyProperties["keyPassword"] as String? ?: ""
            storeFile = keyProperties["storeFile"]?.let { file(it) }
            storePassword = keyProperties["storePassword"] as String? ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.huddlconnect.connect"
        minSdk = 24
        // Explicit value required — Google Play mandates API 35 for new apps
        // submitted after August 2024.  Do NOT rely on flutter.targetSdkVersion
        // which may resolve to an older value depending on the Flutter SDK version.
        targetSdk = 35
        // VERSION-SKEW-1: read from pubspec.yaml via the Flutter gradle plugin.
        // dev.flutter.flutter-gradle-plugin (applied above) exposes these from
        // pubspec `version: x.y.z+build` → versionName=x.y.z, versionCode=build.
        // pubspec is now the SINGLE source of truth for version across iOS+Android.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Multidex: required when the app exceeds 64K method references.
        // Without this, secondary DEX classes (e.g. UCropFileProvider from
        // image_cropper) are not found at runtime → ClassNotFoundException crash.
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Multidex support: required when app exceeds 64K method limit.
    // multiDexEnabled = true in defaultConfig is not sufficient on its own —
    // the library must also be declared here so it is included in the APK/AAB.
    // This ensures secondary DEX classes (e.g. UCropFileProvider from image_cropper)
    // are loaded correctly and avoids ClassNotFoundException crashes at runtime.
    implementation("androidx.multidex:multidex:2.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
