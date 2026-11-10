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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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
        if (isBetaBuild) {
            applicationIdSuffix = ".beta"
        }
        manifestPlaceholders["appLabel"] = if (isBetaBuild) "YOMI Beta" else "YOMI"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (isBetaBuild) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("production")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
