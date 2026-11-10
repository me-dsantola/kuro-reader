package com.kuroreader.kuro_reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private var channel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var batteryPercent: Int? = null
    private var charging = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectivity get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "yomi/device_state")
        channel?.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        stopMonitoring()
        events = sink
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_BATTERY_CHANGED) updateBattery(intent)
                publish()
            }
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply {
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        }
        val battery = if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
        if (battery != null) updateBattery(battery)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publish()
            override fun onLost(network: Network) = publish()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
        }
        try {
            if (Build.VERSION.SDK_INT >= 24) {
                connectivity.registerDefaultNetworkCallback(callback)
            } else {
                connectivity.registerNetworkCallback(
                    NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), callback
                )
            }
            networkCallback = callback
        } catch (_: SecurityException) {
            // A failed observation is unknown, not evidence of an offline phone.
        }
        publish()
    }

    private fun updateBattery(intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
        batteryPercent = if (level >= 0 && scale > 0 && status != BatteryManager.BATTERY_STATUS_UNKNOWN) (100 * level / scale).coerceIn(0, 100) else null
        charging = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
    }

    @Suppress("DEPRECATION")
    private fun internetState(): String = try {
        if (Build.VERSION.SDK_INT >= 23) {
            val network = connectivity.activeNetwork
            val capabilities = if (network == null) null else connectivity.getNetworkCapabilities(network)
            if (capabilities != null && capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) "online" else "offline"
        } else {
            if (connectivity.activeNetworkInfo?.isConnected == true) "online" else "offline"
        }
    } catch (_: SecurityException) { "unknown" }

    private fun publish() {
        mainHandler.post {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            events?.success(mapOf(
                "batteryPercent" to batteryPercent,
                "charging" to charging,
                "powerSaving" to power.isPowerSaveMode,
                "internet" to internetState()
            ))
        }
    }

    override fun onCancel(arguments: Any?) = stopMonitoring()

    private fun stopMonitoring() {
        events = null
        receiver?.let { try { unregisterReceiver(it) } catch (_: IllegalArgumentException) {} }
        receiver = null
        networkCallback?.let { try { connectivity.unregisterNetworkCallback(it) } catch (_: IllegalArgumentException) {} }
        networkCallback = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopMonitoring()
        channel?.setStreamHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
