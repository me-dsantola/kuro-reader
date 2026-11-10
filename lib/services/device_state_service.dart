import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum InternetState { unknown, online, offline }

@immutable
class DeviceStatus {
  final int? batteryPercent;
  final bool charging;
  final bool powerSaving;
  final InternetState internet;
  final bool slow;

  const DeviceStatus({
    this.batteryPercent,
    this.charging = false,
    this.powerSaving = false,
    this.internet = InternetState.unknown,
    this.slow = false,
  });

  bool get lowBattery =>
      batteryPercent != null && batteryPercent! <= 20 && !charging;
  bool get reduceEffects => lowBattery || powerSaving;
}

/// Android reports connectivity and battery. Slow requests never imply offline.
class DeviceStateService extends ValueNotifier<DeviceStatus> {
  static final instance = DeviceStateService();
  static const _events = EventChannel('yomi/device_state');
  StreamSubscription<dynamic>? _subscription;
  final Set<int> _waiting = {};
  final List<bool> _recent = [];
  int _nextRequest = 0;
  bool _disposed = false;

  DeviceStateService() : super(const DeviceStatus());

  void start() {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _subscription != null) {
      return;
    }
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) applyNativeState(event);
      },
      // Unsupported platforms remain unknown, rather than falsely offline.
      onError: (Object _) {},
    );
  }

  @visibleForTesting
  void applyNativeState(Map<dynamic, dynamic> event) {
    final rawBattery = event['batteryPercent'];
    final battery = rawBattery is int && rawBattery >= 0 && rawBattery <= 100
        ? rawBattery
        : null;
    final internet = switch (event['internet']) {
      'online' => InternetState.online,
      'offline' => InternetState.offline,
      _ => InternetState.unknown,
    };
    if (internet != value.internet) _recent.clear();
    value = DeviceStatus(
      batteryPercent: battery,
      charging: event['charging'] == true,
      powerSaving: event['powerSaving'] == true,
      internet: internet,
      slow:
          internet != InternetState.offline &&
          (_waiting.isNotEmpty || _recent.where((s) => s).length >= 2),
    );
  }

  /// Observe existing app traffic; no background speed tests or polling.
  Future<T> observe<T>(Future<T> Function() operation) async {
    if (_disposed) return operation();
    final id = _nextRequest++;
    var delayed = false;
    final timer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      delayed = true;
      _waiting.add(id);
      _publishNetwork();
    });
    try {
      return await operation();
    } finally {
      timer.cancel();
      _waiting.remove(id);
      if (!_disposed) {
        _recent.add(delayed);
        if (_recent.length > 3) _recent.removeAt(0);
        _publishNetwork();
      }
    }
  }

  void _publishNetwork() {
    final old = value;
    final slow =
        old.internet != InternetState.offline &&
        (_waiting.isNotEmpty || _recent.where((s) => s).length >= 2);
    if (slow == old.slow) return;
    value = DeviceStatus(
      batteryPercent: old.batteryPercent,
      charging: old.charging,
      powerSaving: old.powerSaving,
      internet: old.internet,
      slow: slow,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
