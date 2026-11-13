package com.kuroreader.kuro_reader

import android.app.Activity
import android.app.backup.BackupManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.net.NetworkRequest
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var deviceEvents: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var batteryReceiver: BroadcastReceiver? = null

    private fun publishDeviceState() {
        runOnUiThread { deviceEvents?.success(readDeviceState()) }
    }

    private fun stopDeviceEvents() {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        networkCallback?.let { callback -> runCatching { manager?.unregisterNetworkCallback(callback) } }
        batteryReceiver?.let { receiver -> runCatching { unregisterReceiver(receiver) } }
        networkCallback = null
        batteryReceiver = null
        deviceEvents = null
    }

    private fun startDeviceEvents(events: EventChannel.EventSink) {
        stopDeviceEvents()
        deviceEvents = events
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publishDeviceState()
            override fun onLost(network: Network) = publishDeviceState()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publishDeviceState()
        }
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            manager?.registerDefaultNetworkCallback(callback)
        } else {
            manager?.registerNetworkCallback(NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), callback)
        }
        networkCallback = callback
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) = publishDeviceState()
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply {
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
        batteryReceiver = receiver
        publishDeviceState()
    }

    override fun onDestroy() {
        stopDeviceEvents()
        super.onDestroy()
    }
    private var pendingImageResult: MethodChannel.Result? = null
    private val pickImageRequestCode = 9401
    private val autoBackupPrefsName = "kuro_auto_backup_prefs"
    private val legacyBackupPrefsName = "yomi_auto_backup_prefs"
    private val autoBackupFileName = "kuro_auto_backup.json"
    private val legacyBackupFileName = "yomi_auto_backup.txt"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "yomi/device_state")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) = startDeviceEvents(events)
                override fun onCancel(arguments: Any?) = stopDeviceEvents()
            })
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "yomi/device_state_query",
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
                    val chooser = Intent.createChooser(intent, "Escolher imagem para o Kuro Reader")
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
        // 1. SharedPreferences (both modern Kuro and legacy Yomi prefs)
        try {
            getSharedPreferences(autoBackupPrefsName, Context.MODE_PRIVATE)
                .edit()
                .putString("payload", payload)
                .putLong("updatedAt", System.currentTimeMillis())
                .apply()
            getSharedPreferences(legacyBackupPrefsName, Context.MODE_PRIVATE)
                .edit()
                .putString("payload", payload)
                .putLong("updatedAt", System.currentTimeMillis())
                .apply()
            savedAny = true
        } catch (_: Exception) {}

        // 2. Internal app files
        try {
            File(filesDir, autoBackupFileName).writeText(payload, Charsets.UTF_8)
            File(filesDir, legacyBackupFileName).writeText(payload, Charsets.UTF_8)
            savedAny = true
        } catch (_: Exception) {}

        // 3. Shared Downloads/KuroReader & Downloads/YOMI
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                for ((folder, fileName, mime) in listOf(
                    Triple("KuroReader", autoBackupFileName, "application/json"),
                    Triple("YOMI", legacyBackupFileName, "text/plain"),
                )) {
                    val projection = arrayOf(MediaStore.MediaColumns._ID)
                    val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
                    val selectionArgs = arrayOf(fileName)
                    var existingUri: Uri? = null
                    resolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val id = cursor.getLong(0)
                            existingUri = ContentUris.withAppendedId(collection, id)
                        }
                    }
                    val targetUri = existingUri ?: run {
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                            put(
                                MediaStore.MediaColumns.RELATIVE_PATH,
                                Environment.DIRECTORY_DOWNLOADS + "/$folder",
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
                }
            } else {
                @Suppress("DEPRECATION")
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                for ((folder, fileName) in listOf(
                    Pair("KuroReader", autoBackupFileName),
                    Pair("YOMI", legacyBackupFileName),
                )) {
                    val dir = File(downloadsDir, folder)
                    if (!dir.exists()) dir.mkdirs()
                    File(dir, fileName).writeText(payload, Charsets.UTF_8)
                    savedAny = true
                }
            }
        } catch (_: Exception) {}

        try {
            BackupManager(this).dataChanged()
        } catch (_: Exception) {}

        return savedAny
    }

    private fun loadAutoBackupPayload(): String? {
        // 1. Check SharedPreferences (Kuro first, then legacy Yomi)
        for (prefsName in listOf(autoBackupPrefsName, legacyBackupPrefsName)) {
            try {
                val fromPrefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                    .getString("payload", null)
                if (!fromPrefs.isNullOrBlank()) return fromPrefs
            } catch (_: Exception) {}
        }

        // 2. Check internal filesDir (Kuro first, then legacy Yomi)
        for (fileName in listOf(autoBackupFileName, legacyBackupFileName)) {
            try {
                val internalFile = File(filesDir, fileName)
                if (internalFile.exists()) {
                    val text = internalFile.readText(Charsets.UTF_8).trim()
                    if (text.isNotEmpty()) return text
                }
            } catch (_: Exception) {}
        }

        // 3. Check shared Downloads via MediaStore (Android 10+)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                for (targetName in listOf(autoBackupFileName, legacyBackupFileName)) {
                    val projection = arrayOf(MediaStore.MediaColumns._ID)
                    val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
                    val selectionArgs = arrayOf(targetName)
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
            }
        } catch (_: Exception) {}

        // 4. Fallback public directory check
        try {
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            for (relativePath in listOf("KuroReader/$autoBackupFileName", "YOMI/$legacyBackupFileName")) {
                val file = File(downloadsDir, relativePath)
                if (file.exists()) {
                    val text = file.readText(Charsets.UTF_8).trim()
                    if (text.isNotEmpty()) return text
                }
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
