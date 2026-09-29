plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.personal.fmp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // prod 的 applicationId 與舊版相同（ADR 0008 §決定 3），舊資料與
        // Keystore 憑證才讀得到；改它要另立 ADR。
        applicationId = "com.personal.fmp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // release 簽名在發版工作接 key.properties（M1 PR 13），先用 debug 簽名。
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // flavor 只改身分（app/AGENTS.md § App 身分）；App 名稱在
    // src/<flavor>/res/values/strings.xml。AGP 9 起 resValue() 預設停用，所以
    // 不用它（https://docs.flutter.dev/deployment/flavors）。
    flavorDimensions += "identity"
    productFlavors {
        create("dev") {
            dimension = "identity"
            applicationIdSuffix = ".dev"
        }
        create("prod") {
            dimension = "identity"
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
