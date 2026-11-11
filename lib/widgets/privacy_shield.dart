import 'package:flutter/material.dart';
import '../screens/home_tabs.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';

/// Masks app content when the lifecycle is not active, including pushed routes,
/// whenever the user has Privacy Protection enabled.
class PrivacyShield extends StatefulWidget {
  final Widget child;
  const PrivacyShield({super.key, required this.child});

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  AppLifecycleState? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = WidgetsBinding.instance.lifecycleState;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_state != state && mounted) {
      setState(() => _state = state);
    }
  }

  bool get _shielded =>
      StorageService.privacyProtectionEnabled &&
      _state != null &&
      _state != AppLifecycleState.resumed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      StorageService.privacyProtectionNotifier,
      ProfilePaletteService.paletteNotifier,
    ]),
    builder: (context, _) {
      final shielded = _shielded;
      final palette = ProfilePaletteService.paletteNotifier.value;
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: shielded,
            child: IgnorePointer(ignoring: shielded, child: widget.child),
          ),
          if (shielded)
            ColoredBox(
              color: YomiPalette.pitchBlack,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_moon_rounded,
                      size: 64,
                      color: palette.primary,
                    ),
                    const SizedBox(height: 16),
                    const YomiEnsoLogo(fontSize: 28),
                    const SizedBox(height: 8),
                    const Text(
                      'Proteção de Privacidade Ativa',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
