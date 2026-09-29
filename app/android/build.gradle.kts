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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_js 0.8.7 的 android/build.gradle 把 Kotlin 的 jvmTarget 寫死成 1.8，
// 卻沒設 Java 的 compileOptions，AGP 的預設（11）與它不一致，
// compileDebugKotlin 會失敗（Inconsistent JVM Target Compatibility）。把那個
// 子專案的 Java 也設成 1.8。它自己的 build.gradle 不設 compileOptions，所以在
// 套用 library 插件時設定不會被蓋掉。升 flutter_js 時看還需不需要。
subprojects {
    if (name == "flutter_js") {
        pluginManager.withPlugin("com.android.library") {
            extensions.getByName("android").withGroovyBuilder {
                "compileOptions" {
                    setProperty("sourceCompatibility", JavaVersion.VERSION_1_8)
                    setProperty("targetCompatibility", JavaVersion.VERSION_1_8)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
