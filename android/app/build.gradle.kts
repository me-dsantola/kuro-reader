import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kuroreader.kuro_reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    val isBetaBuild = providers.gradleProperty("betaBuild").orNull == "true"

    // Beta QA APKs may use the Android debug key. A stable/public release
    // must be signed with the owner's private keystore, never the debug key.
    signingConfigs {
        create("production") {
            val path = System.getenv("YOMI_KEYSTORE_PATH")
            if (!path.isNullOrBlank()) {
                storeFile = file(path)
            }
            storePassword = System.getenv("YOMI_STORE_PASSWORD")
            keyAlias = System.getenv("YOMI_KEY_ALIAS")
            keyPassword = System.getenv("YOMI_KEY_PASSWORD")
        }
    }

    defaultConfig {
        applicationId = "com.kuroreader.kuro_reader"
        manifestPlaceholders["appLabel"] = if (isBetaBuild) "Yomi Beta" else "Yomi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            val prodPath = System.getenv("YOMI_KEYSTORE_PATH")
            signingConfig = if (!prodPath.isNullOrBlank() && file(prodPath).exists()) {
                signingConfigs.getByName("production")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
