import 'package:flutter/material.dart';
import '../screens/home_tabs.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import 'yomi_blobatar_studio.dart';

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
      StorageService.profileNotifier,
      ProfilePaletteService.paletteNotifier,
    ]),
    builder: (context, _) {
      final shielded = _shielded;
      final palette = ProfilePaletteService.paletteNotifier.value;
      final profile = StorageService.profileNotifier.value;

      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: shielded,
            child: IgnorePointer(ignoring: shielded, child: widget.child),
          ),
          if (shielded)
            Material(
              color: YomiPalette.pitchBlack,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Brilho radial atmosférico acompanhando a paleta ativa
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.15),
                          radius: 0.85,
                          colors: [
                            palette.primary.withValues(alpha: 0.20),
                            palette.bannerDark.withValues(alpha: 0.45),
                            YomiPalette.pitchBlack,
                          ],
                          stops: const [0.0, 0.52, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 30,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: palette.primary.withValues(alpha: 0.32),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.65),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: palette.primary.withValues(alpha: 0.14),
                              blurRadius: 28,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const YomiEnsoLogo(fontSize: 28),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: YomiPalette.pitchBlack,
                                border: Border.all(
                                  color: palette.primary.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                              child: YomiProfileBlobatar(
                                profile: profile,
                                size: 68,
                                adaptiveHue: palette.hue,
                                interactiveCycleOnTap: false,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Proteção de Privacidade Ativa',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sua leitura está oculta enquanto o aplicativo está em segundo plano.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 12,
                                height: 1.35,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: palette.primary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 13,
                                    color: palette.secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Modo Privado YOMI',
                                    style: TextStyle(
                                      color: palette.soft,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
