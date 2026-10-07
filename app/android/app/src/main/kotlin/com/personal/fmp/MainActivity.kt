package com.personal.fmp

import android.content.Context
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

// 這兩個覆寫沒有自動閘門，改動後要在 Android 實機驗（app/AGENTS.md § 平台層）。
class MainActivity : AudioServiceActivity() {
    // audio_service 的 AudioServicePlugin.getFlutterEngine 以
    // DartEntrypoint.createDefault() 啟動引擎，不帶 intent 的 dart_entrypoint_args，
    // `--fmp-dev-plugin`（開發入口）在 Android 就失效。所以快取裡沒有引擎時自己
    // 建，帶著 getDartEntrypointArgs() 啟動，再放進 audio_service 用的快取鍵，
    // 它的服務之後拿到的是同一個引擎。
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        val id = AudioServicePlugin.getFlutterEngineId()
        cache.get(id)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
            getDartEntrypointArgs(),
        )
        cache.put(id, engine)
        return engine
    }

    // Flutter 的 PlatformPlugin.popSystemNavigator 在根 route 沒得 pop 時預設
    // finish() 這個 Activity，返回鍵就直接結束 App、播放也停。FlutterActivity 留了
    // 這個給子類別的掛鉤：改成退到背景，引擎與播放都不動。
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
}
