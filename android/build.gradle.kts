allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // file_picker 11.0.3 只在 AGP < 9 時才套用 kotlin-android，AGP 9 以上它預期吃內建 Kotlin。
    // 但 Flutter Gradle Plugin 是用正則掃 build.gradle 判斷子專案有沒有宣告 KGP，看不出那行被
    // `if (!isAgp9OrAbove)` 包住，於是也不幫它補套用（FlutterPluginUtils.detectApplyingKotlinGradlePlugin）。
    // 兩邊都以為對方會做，結果它的 Kotlin 原始碼沒人編譯，:app 會在 GeneratedPluginRegistrant
    // 撞到 cannot find symbol FilePickerPlugin。這裡手動補上。
    // 全域 android.builtInKotlin 為何不能開，見 gradle.properties。
    if (project.name == "file_picker") {
        project.pluginManager.apply("org.jetbrains.kotlin.android")
    }

    // Fix namespace and compileSdk for old plugins
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android is com.android.build.gradle.LibraryExtension) {
                if (android.namespace.isNullOrEmpty()) {
                    android.namespace = project.group.toString().ifEmpty { "com.example.${project.name.replace("-", "_")}" }
                }
                // Force compileSdk to 36 for all subprojects to fix compatibility issues
                android.compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
