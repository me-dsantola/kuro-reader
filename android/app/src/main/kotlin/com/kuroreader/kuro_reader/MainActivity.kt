package com.kuroreader.kuro_reader

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var pendingImageResult: MethodChannel.Result? = null
    private val pickImageRequestCode = 9401

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "yomi/device_state",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getState") {
                result.success(readDeviceState())
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "yomi/image_picker",
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                if (pendingImageResult != null) {
                    result.error("BUSY", "Picker already active", null)
                    return@setMethodCallHandler
                }
                pendingImageResult = result
                try {
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    val chooser = Intent.createChooser(intent, "Escolher imagem para o YOMI")
                    startActivityForResult(chooser, pickImageRequestCode)
                } catch (e: Exception) {
                    pendingImageResult = null
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickImageRequestCode) {
            val callback = pendingImageResult
            pendingImageResult = null
            if (callback == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }
            val uri: Uri = data.data!!
            try {
                val input = contentResolver.openInputStream(uri)
                if (input == null) {
                    callback.success(null)
                    return
                }
                val dir = File(filesDir, "profile_media")
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                val outFile = File(dir, "yomi_picked_${System.currentTimeMillis()}.jpg")
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
                input.close()
                callback.success(outFile.absolutePath)
            } catch (e: Exception) {
                callback.success(null)
            }
        }
    }

    private fun readDeviceState(): Map<String, Any> {
        val batteryIntent = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) (level * 100) / scale else -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val powerSaving = power?.isPowerSaveMode == true

        val connectivity =
            getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val internet = if (connectivity == null) {
            "unknown"
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = connectivity.activeNetwork
            val caps = connectivity.getNetworkCapabilities(network)
            val validated =
                caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            if (validated) "online" else "offline"
        } else {
            @Suppress("DEPRECATION")
            val active = connectivity.activeNetworkInfo
            @Suppress("DEPRECATION")
            if (active != null && active.isConnected) "online" else "offline"
        }

        return mapOf(
            "batteryPercent" to percent,
            "charging" to charging,
            "powerSaving" to powerSaving,
            "internet" to internet,
        )
    }
}
