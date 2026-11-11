package com.kuroreader.kuro_reader

import android.app.Activity
import android.app.backup.BackupManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var pendingImageResult: MethodChannel.Result? = null
    private val pickImageRequestCode = 9401
    private val autoBackupPrefsName = "yomi_auto_backup_prefs"
    private val autoBackupFileName = "yomi_auto_backup.txt"

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "yomi/auto_backup",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveAutoBackup" -> {
                    val payload = call.argument<String>("payload")
                    if (payload.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        result.success(saveAutoBackupPayload(payload))
                    }
                }
                "loadAutoBackup" -> {
                    result.success(loadAutoBackupPayload())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveAutoBackupPayload(payload: String): Boolean {
        var savedAny = false
        try {
            getSharedPreferences(autoBackupPrefsName, Context.MODE_PRIVATE)
                .edit()
                .putString("payload", payload)
                .putLong("updatedAt", System.currentTimeMillis())
                .apply()
            savedAny = true
        } catch (_: Exception) {}

        try {
            File(filesDir, autoBackupFileName).writeText(payload, Charsets.UTF_8)
            savedAny = true
        } catch (_: Exception) {}

        // Save to shared Downloads/YOMI so it survives app uninstallation on the phone
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val projection = arrayOf(MediaStore.MediaColumns._ID)
                val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
                val selectionArgs = arrayOf(autoBackupFileName)
                var existingUri: Uri? = null
                resolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val id = cursor.getLong(0)
                        existingUri = ContentUris.withAppendedId(collection, id)
                    }
                }
                val targetUri = existingUri ?: run {
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, autoBackupFileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                        put(
                            MediaStore.MediaColumns.RELATIVE_PATH,
                            Environment.DIRECTORY_DOWNLOADS + "/YOMI",
                        )
                    }
                    resolver.insert(collection, values)
                }
                if (targetUri != null) {
                    resolver.openOutputStream(targetUri, "wt")?.use { out ->
                        out.write(payload.toByteArray(Charsets.UTF_8))
                        out.flush()
                    }
                    savedAny = true
                }
            } else {
                @Suppress("DEPRECATION")
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "YOMI",
                )
                if (!dir.exists()) dir.mkdirs()
                File(dir, autoBackupFileName).writeText(payload, Charsets.UTF_8)
                savedAny = true
            }
        } catch (_: Exception) {}

        try {
            BackupManager(this).dataChanged()
        } catch (_: Exception) {}

        return savedAny
    }

    private fun loadAutoBackupPayload(): String? {
        // 1. Check SharedPreferences restored by YomiBackupAgent
        try {
            val fromPrefs = getSharedPreferences(autoBackupPrefsName, Context.MODE_PRIVATE)
                .getString("payload", null)
            if (!fromPrefs.isNullOrBlank()) return fromPrefs
        } catch (_: Exception) {}

        // 2. Check internal filesDir restored by Android Auto Backup
        try {
            val internalFile = File(filesDir, autoBackupFileName)
            if (internalFile.exists()) {
                val text = internalFile.readText(Charsets.UTF_8).trim()
                if (text.isNotEmpty()) return text
            }
        } catch (_: Exception) {}

        // 3. Check shared Downloads/YOMI via MediaStore (Android 10+)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val projection = arrayOf(MediaStore.MediaColumns._ID)
                val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
                val selectionArgs = arrayOf(autoBackupFileName)
                resolver.query(
                    collection,
                    projection,
                    selection,
                    selectionArgs,
                    "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(0)
                        val uri = ContentUris.withAppendedId(collection, id)
                        resolver.openInputStream(uri)?.use { input ->
                            val text = input.bufferedReader(Charsets.UTF_8).readText().trim()
                            if (text.isNotEmpty()) return text
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 4. Fallback public directory check
        try {
            @Suppress("DEPRECATION")
            val legacyFile = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "YOMI/$autoBackupFileName",
            )
            if (legacyFile.exists()) {
                val text = legacyFile.readText(Charsets.UTF_8).trim()
                if (text.isNotEmpty()) return text
            }
        } catch (_: Exception) {}

        return null
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
