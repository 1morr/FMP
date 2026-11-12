package com.personal.fmpx.glass_probe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Experiment (M0 ticket 05b): Android has no public "reduce transparency"
// setting; the channel answers null so the probe records that.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fmpx/a11y")
            .setMethodCallHandler { call, result ->
                if (call.method == "reduceTransparency") result.success(null) else result.notImplemented()
            }
    }
}
