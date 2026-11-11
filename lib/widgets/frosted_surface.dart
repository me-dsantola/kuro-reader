import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/appearance_controller.dart';
import '../services/device_state_service.dart';
import '../services/profile_palette_service.dart';

/// Blur is restricted to the toolbar/dock bounds, with a translucent glass sheen and border.
/// Enabled by default, and automatically disabled when the device is in power-saving mode
/// or high-contrast / reduced-motion accessibility mode.
class FrostedSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;

  const FrostedSurface({
    super.key,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppearanceController.instance,
        DeviceStateService.instance,
        ProfilePaletteService.paletteNotifier,
      ]),
      builder: (context, _) {
        final preferences = AppearanceController.instance.value;
        final deviceState = DeviceStateService.instance.value;
        final palette = ProfilePaletteService.paletteNotifier.value;
        final powerSavingOrContrast =
            deviceState.reduceEffects ||
            MediaQuery.highContrastOf(context) ||
            MediaQuery.disableAnimationsOf(context);
        final glass =
            preferences.style == InterfaceStyle.glass && !powerSavingOrContrast;

        final surface = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: powerSavingOrContrast
                  ? const [Color(0xFF070709), Color(0xFF121217)]
                  : glass
                  ? [
                      const Color(0xFF202030).withValues(alpha: 0.46),
                      const Color(0xFF0A0A12).withValues(alpha: 0.58),
                    ]
                  : [
                      const Color(0xFF0E0E14).withValues(alpha: 0.94),
                      const Color(0xFF14141C).withValues(alpha: 0.90),
                    ],
            ),
            border: borderRadius != null
                ? Border.all(
                    color: glass
                        ? Colors.white.withValues(alpha: 0.16)
                        : palette.secondary.withValues(alpha: 0.14),
                    width: glass ? 1.15 : 1.0,
                  )
                : Border(
                    bottom: BorderSide(
                      color: palette.secondary.withValues(
                        alpha: glass ? 0.28 : 0.16,
                      ),
                    ),
                  ),
            boxShadow: (glass && borderRadius != null)
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
        if (powerSavingOrContrast) {
          return borderRadius != null
              ? ClipRRect(borderRadius: borderRadius!, child: surface)
              : ClipRect(child: surface);
        }
        final blurred = BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glass ? 22 : 8,
            sigmaY: glass ? 22 : 8,
          ),
          child: surface,
        );
        return borderRadius != null
            ? ClipRRect(borderRadius: borderRadius!, child: blurred)
            : ClipRect(child: blurred);
      },
    );
  }
}
