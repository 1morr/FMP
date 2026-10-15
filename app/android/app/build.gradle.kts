import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 發版簽名（app/AGENTS.md § 發版）：與舊版同一把金鑰（ADR 0008 §決定 3），
// 舊版使用者才升得上來。android/key.properties 只在發版 workflow 裡由 secrets
// 寫出（已 gitignore）；沒有這個檔時 release 用 debug 簽名，本機與 CI 的建置
// 照常能跑。檔案在但缺欄位就讓建置失敗，不默默退回 debug。
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties: Properties? = if (keyPropertiesFile.exists()) {
    Properties().apply { keyPropertiesFile.inputStream().use { load(it) } }.also { properties ->
        val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            .filter { properties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException("android/key.properties is missing ${missing.joinToString()}")
        }
    }
} else {
    null
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

    signingConfigs {
        if (keyProperties != null) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 在 Flutter 預設的規則之外加上 audio_service 反射用的 keep 規則。
            proguardFiles("proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (keyProperties != null) "release" else "debug")
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

dependencies {
    // MediaKeyFix.java 繼承 audio_service 的 MediaSessionCallback，編譯期要看得到
    // MediaSessionCompat；audio_service 把它宣告為 implementation，不會傳遞給 app。
    // 版本跟 audio_service 0.18.19 的 build.gradle.kts 一致（釘版測試
    // audio_service_internals_test.dart 提醒升級時一起檢查）。
    implementation("androidx.media:media:1.7.0")
}

flutter {
    source = "../.."
}
