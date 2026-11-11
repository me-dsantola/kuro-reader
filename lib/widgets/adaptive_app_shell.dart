import 'dart:async';
import 'package:flutter/material.dart';
import '../services/device_state_service.dart';
import '../services/profile_palette_service.dart';
import 'frosted_surface.dart';

class AdaptiveAppShell extends StatefulWidget {
  final Widget child;
  final DeviceStateService? service;
  final Duration slowDisplayDelay;
  final Duration autoHideDuration;

  const AdaptiveAppShell({
    super.key,
    required this.child,
    this.service,
    this.slowDisplayDelay = Duration.zero,
    this.autoHideDuration = const Duration(seconds: 4),
  });

  @override
  State<AdaptiveAppShell> createState() => _AdaptiveAppShellState();
}

class _AdaptiveAppShellState extends State<AdaptiveAppShell> {
  Timer? _hideTimer;
  Timer? _slowDelayTimer;
  bool _visible = false;
  bool _slowReady = false;
  String _lastSignature = '';

  DeviceStateService get _activeService =>
      widget.service ?? DeviceStateService.instance;

  @override
  void initState() {
    super.initState();
    _activeService.addListener(_onServiceChanged);
    _syncState(initial: true);
  }

  @override
  void didUpdateWidget(covariant AdaptiveAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldService = oldWidget.service ?? DeviceStateService.instance;
    final newService = _activeService;
    if (!identical(oldService, newService)) {
      oldService.removeListener(_onServiceChanged);
      newService.addListener(_onServiceChanged);
      _syncState(initial: true);
    }
  }

  @override
  void dispose() {
    _activeService.removeListener(_onServiceChanged);
    _hideTimer?.cancel();
    _slowDelayTimer?.cancel();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    _syncState(initial: false);
  }

  void _syncState({required bool initial}) {
    final state = _activeService.value;

    // Handle optional slow-connection delay before displaying slow marker
    if (state.slow && state.internet != InternetState.offline) {
      if (widget.slowDisplayDelay == Duration.zero) {
        _slowReady = true;
      } else if (!_slowReady && _slowDelayTimer == null) {
        _slowDelayTimer = Timer(widget.slowDisplayDelay, () {
          _slowDelayTimer = null;
          if (!mounted) return;
          setState(() {
            _slowReady = true;
            _triggerPopupIfNeeded();
          });
        });
      }
    } else {
      _slowDelayTimer?.cancel();
      _slowDelayTimer = null;
      _slowReady = false;
    }

    if (initial) {
      _triggerPopupIfNeeded();
    } else {
      setState(_triggerPopupIfNeeded);
    }
  }

  List<_StateMarkerItem> _buildMarkers(DeviceStatus state) {
    final items = <_StateMarkerItem>[];
    if (state.internet == InternetState.offline) {
      items.add(
        const _StateMarkerItem(
          icon: Icons.wifi_off_rounded,
          label: 'Sem internet · usando dados salvos',
        ),
      );
    } else if (state.slow && _slowReady) {
      items.add(
        const _StateMarkerItem(
          icon: Icons.network_check_rounded,
          label: 'Conexão lenta · carregamento econômico',
        ),
      );
    }
    if (state.lowBattery) {
      final level = state.batteryPercent != null
          ? 'Bateria ${state.batteryPercent}%'
          : 'Economia de bateria';
      items.add(
        _StateMarkerItem(
          icon: Icons.battery_saver_rounded,
          label: '$level · economia ativa',
        ),
      );
    } else if (state.powerSaving) {
      items.add(
        const _StateMarkerItem(
          icon: Icons.energy_savings_leaf_rounded,
          label: 'Economia de energia · efeitos reduzidos',
        ),
      );
    }
    return items;
  }

  void _triggerPopupIfNeeded() {
    final markers = _buildMarkers(_activeService.value);
    if (markers.isEmpty) {
      _hideTimer?.cancel();
      _hideTimer = null;
      _visible = false;
      _lastSignature = '';
      return;
    }
    final signature = markers.map((m) => m.label).join('|');
    if (signature != _lastSignature) {
      _lastSignature = signature;
      _visible = true;
      _hideTimer?.cancel();
      _hideTimer = Timer(widget.autoHideDuration, () {
        if (mounted) {
          setState(() => _visible = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _activeService.value;
    final media = MediaQuery.of(context);
    final adaptedMedia = state.reduceEffects
        ? media.copyWith(disableAnimations: true, highContrast: true)
        : media;
    final adaptedChild = MediaQuery(data: adaptedMedia, child: widget.child);
    final markers = _buildMarkers(state);

    return Stack(
      fit: StackFit.expand,
      children: [
        adaptedChild,
        if (_visible && markers.isNotEmpty)
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ValueListenableBuilder<ProfileAdaptivePalette>(
                    valueListenable: ProfilePaletteService.paletteNotifier,
                    builder: (context, palette, _) => Material(
                      color: Colors.transparent,
                      child: FrostedSurface(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 460),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: palette.primary.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Semantics(
                            liveRegion: true,
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final marker in markers)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        marker.icon,
                                        size: 15,
                                        color: palette.secondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          marker.label,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFFAFAFA),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StateMarkerItem {
  final IconData icon;
  final String label;
  const _StateMarkerItem({required this.icon, required this.label});
}
