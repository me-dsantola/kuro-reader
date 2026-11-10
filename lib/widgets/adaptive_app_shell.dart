import 'package:flutter/material.dart';
import '../services/device_state_service.dart';

/// A persistent, accessible status above every route, including the reader.
class AdaptiveAppShell extends StatelessWidget {
  final Widget child;
  final DeviceStateService? service;
  const AdaptiveAppShell({super.key, required this.child, this.service});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DeviceStatus>(
    valueListenable: service ?? DeviceStateService.instance,
    child: child,
    builder: (context, status, child) {
      final media = MediaQuery.of(context);
      final offline = status.internet == InternetState.offline;
      final slow = !offline && status.slow;
      final messages = <String>[
        if (offline) 'Sem internet · leia seus capítulos na aba Offline',
        if (slow) 'Carregamento lento · aguardando a rede ou a fonte',
        if (status.lowBattery)
          'Bateria ${status.batteryPercent}% · modo econômico',
        if (!status.lowBattery && status.powerSaving)
          'Economia de bateria ativa',
      ];
      final adapted = MediaQuery(
        data: media.copyWith(
          disableAnimations: media.disableAnimations || status.reduceEffects,
          highContrast: media.highContrast || status.reduceEffects,
          padding: messages.isEmpty
              ? media.padding
              : media.padding.copyWith(top: 0),
          viewPadding: messages.isEmpty
              ? media.viewPadding
              : media.viewPadding.copyWith(top: 0),
        ),
        child: child!,
      );
      final critical = status.lowBattery && status.batteryPercent! <= 5;
      final accent = critical
          ? const Color(0xFFFDA4AF)
          : const Color(0xFFFBCFE8);
      return Column(
        children: [
          if (messages.isNotEmpty)
            Material(
              color: const Color(0xFF121217),
              child: SafeArea(
                bottom: false,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: accent.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          offline
                              ? Icons.wifi_off_rounded
                              : slow
                              ? Icons.network_check_rounded
                              : Icons.battery_saver_rounded,
                          color: accent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            messages.join('\n'),
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(key: const ValueKey('adaptive-content'), child: adapted),
        ],
      );
    },
  );
}
