package com.personal.fmp.dev

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service 的前景服務和這個 Activity 共用同一個 FlutterEngine：關掉畫面
// （按返回、從最近使用滑掉）後 Dart 照常在背景播放（audio_service 的 README
// 〈Custom Android activity〉）。
class MainActivity : AudioServiceActivity() {
    // 媒體鍵修正（事實 A6，MediaKeyFix.java）：Dart 端在 audio_service 的服務建好後
    // 呼叫 install（lib/platform/audio_service_controls.dart）。頻道登記在引擎上，
    // Activity 重建也不必重登。
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
}
