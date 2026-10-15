package com.personal.fmp

import android.content.Context
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

// 這些覆寫沒有自動閘門，改動後要在 Android 實機驗（app/AGENTS.md § 平台層）。
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

    // 媒體鍵修正（#233，MediaKeyFix.java）：Dart 端在 audio_service 服務建好後呼叫
    // install。頻道登記在引擎上，Activity 重建也不必重登。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fmp/media_keys")
            .setMethodCallHandler { call, result ->
                if (call.method == "install") {
                    result.success(MediaKeyFix.install())
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 接回 audio_service 留著的引擎時 Dart 端不會重送返回的狀態，所以一開始就登記。
        setFrameworkHandlesBack(true)
    }

    // 返回鍵一律交給 Flutter。Android 16 起 targetSdk 36 預設啟用 predictive back：
    // 返回不再經 onBackPressed，只走 OnBackInvokedCallback。Flutter 在根 route 沒得
    // pop 時（搜尋分頁）取消登記自己的 callback、讓系統處理，系統只對「從桌面啟動」
    // 的 task 退到背景，其他（adb、通知、別的 App 開的）一律 finish()，下面的
    // popSystemNavigator 也就不會被呼叫。一直登記著，根 route 的返回才會經 Dart 的
    // handlePopRoute → SystemNavigator.pop 走到 popSystemNavigator。
    override fun setFrameworkHandlesBack(frameworkHandlesBack: Boolean) {
        super.setFrameworkHandlesBack(true)
    }

    // Flutter 的 PlatformPlugin.popSystemNavigator 在根 route 沒得 pop 時預設
    // finish() 這個 Activity，返回鍵就直接結束 App。FlutterActivity 留了這個給
    // 子類別的掛鉤：改成退到背景，引擎與播放都不動。
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
}
