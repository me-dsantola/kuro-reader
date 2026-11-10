import '../services/appearance_controller.dart';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Blur is restricted to the toolbar bounds, with a dark gradient for contrast.
class FrostedSurface extends StatelessWidget {
  final Widget child;
  const FrostedSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppearancePreferences>(
      valueListenable: AppearanceController.instance,
      builder: (context, preferences, _) {
        final glass = preferences.style == InterfaceStyle.glass;
        final contrast =
            MediaQuery.highContrastOf(context) ||
            MediaQuery.disableAnimationsOf(context);
        final surface = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF070709).withValues(
                  alpha: contrast
                      ? 1
                      : glass
                      ? 0.88
                      : 0.94,
                ),
                Color(0xFF121217).withValues(
                  alpha: contrast
                      ? 1
                      : glass
                      ? 0.72
                      : 0.76,
                ),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Color(0xFFF472B6).withValues(alpha: 0.18),
              ),
            ),
          ),
          child: child,
        );
        return ClipRect(
          child: contrast
              ? surface
              : BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: glass ? 10 : 6,
                    sigmaY: glass ? 10 : 6,
                  ),
                  child: surface,
                ),
        );
      },
    );
  }
}
