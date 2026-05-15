package com.personal.fmp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pendingManageExternalStorageResult: MethodChannel.Result? = null
    private var pendingStorageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.personal.fmp/platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "isManageExternalStorageGranted" -> result.success(isManageExternalStorageGranted())
                "isStorageGranted" -> result.success(isLegacyStorageGranted())
                "requestManageExternalStorage" -> requestManageExternalStorage(result)
                "requestStorage" -> requestLegacyStorage(result)
                "openAppSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MANAGE_EXTERNAL_STORAGE) {
            pendingManageExternalStorageResult?.success(isManageExternalStorageGranted())
            pendingManageExternalStorageResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == REQUEST_LEGACY_STORAGE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingStorageResult?.success(granted)
            pendingStorageResult = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun isManageExternalStorageGranted(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    private fun isLegacyStorageGranted(): Boolean {
        val permissions = legacyStoragePermissions()
        if (permissions.isEmpty()) return true
        return permissions.all {
            checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestManageExternalStorage(result: MethodChannel.Result) {
        if (isManageExternalStorageGranted()) {
            result.success(true)
            return
        }
        if (pendingManageExternalStorageResult != null) {
            result.error("request_in_progress", "Storage permission request already active", null)
            return
        }

        pendingManageExternalStorageResult = result
        val appSettingsIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
        }

        try {
            startActivityForResult(appSettingsIntent, REQUEST_MANAGE_EXTERNAL_STORAGE)
        } catch (_: Exception) {
            try {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                    REQUEST_MANAGE_EXTERNAL_STORAGE
                )
            } catch (_: Exception) {
                pendingManageExternalStorageResult?.success(false)
                pendingManageExternalStorageResult = null
            }
        }
    }

    private fun requestLegacyStorage(result: MethodChannel.Result) {
        if (isLegacyStorageGranted()) {
            result.success(true)
            return
        }
        if (pendingStorageResult != null) {
            result.error("request_in_progress", "Storage permission request already active", null)
            return
        }

        val permissions = legacyStoragePermissions()
        if (permissions.isEmpty()) {
            result.success(true)
            return
        }

        pendingStorageResult = result
        requestPermissions(permissions, REQUEST_LEGACY_STORAGE)
    }

    private fun legacyStoragePermissions(): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        ) {
            return emptyArray()
        }

        return arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        )
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val REQUEST_MANAGE_EXTERNAL_STORAGE = 6401
        private const val REQUEST_LEGACY_STORAGE = 6402
    }
}
