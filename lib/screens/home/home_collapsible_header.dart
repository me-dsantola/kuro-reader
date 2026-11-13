import 'package:flutter/material.dart';
import '../../widgets/individual_glass_capsule.dart';
import 'featured_preload_controller.dart';

/// Filtra notificações de rolagem vertical da Home para coordenar o header e a barra de navegação.
class VerticalScrollCoordinator extends ChangeNotifier {
  double _collapseFactor = 0.0; // 0.0 = expandido, 1.0 = recolhido
  double get collapseFactor => _collapseFactor;

  bool handleScrollNotification(ScrollNotification notification) {
    // Ignora estritamente rolagem horizontal (carrosséis/PageView)
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (delta == 0.0) return false;
      if (notification.metrics.pixels <= 0) {
        _setCollapse(0.0);
      } else {
        const sensitivity = 72.0;
        final next = (_collapseFactor + (delta / sensitivity)).clamp(0.0, 1.0);
        _setCollapse(next);
      }
    }
    return false;
  }

  void _setCollapse(double value) {
    if ((_collapseFactor - value).abs() > 0.005) {
      _collapseFactor = value;
      notifyListeners();
    }
  }
}

class HomeCollapsibleHeader extends StatelessWidget {
  final FeaturedPalette previousPalette;
  final FeaturedPalette targetPalette;
  final Animation<double> paletteAnimation;
  final VerticalScrollCoordinator scrollCoordinator;
  final VoidCallback? onSearchTap;
  final Widget? trailingAction;

  const HomeCollapsibleHeader({
    super.key,
    required this.previousPalette,
    required this.targetPalette,
    required this.paletteAnimation,
    required this.scrollCoordinator,
    this.onSearchTap,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: Listenable.merge([paletteAnimation, scrollCoordinator]),
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(paletteAnimation.value);
        final palette = FeaturedPalette.lerp(previousPalette, targetPalette, t);
        final collapse = reduceMotion
            ? (scrollCoordinator.collapseFactor > 0.5 ? 1.0 : 0.0)
            : scrollCoordinator.collapseFactor;

        const maxHeaderHeight = 64.0;
        const minHeaderHeight = 48.0; // Preserva área mínima de toque (48dp)
        final currentHeight =
            maxHeaderHeight - (maxHeaderHeight - minHeaderHeight) * collapse;

        return Material(
          color: Colors.transparent,
          elevation: 0,
          child: Padding(
            padding: EdgeInsets.only(
              top: topPadding + 4,
              left: 16.0,
              right: 16.0,
            ),
            child: SizedBox(
              height: currentHeight,
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 132,
                    ),
                    child: IndividualGlassCapsule(
                      borderRadius: BorderRadius.circular(18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      surfaceTint: palette.surface,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Container(
                          width: 26 - (4 * collapse),
                          height: 26 - (4 * collapse),
                          decoration: BoxDecoration(
                            color: palette.primary,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Y',
                            style: TextStyle(
                              color: palette.primary.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15 - (2 * collapse),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'YOMI',
                          style: TextStyle(
                            color: palette.onSurface,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            fontSize: 18 - (2 * collapse),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                  const Spacer(),
                  if (onSearchTap != null)
                    IndividualGlassCapsule(
                      isCircle: true,
                      width: 48,
                      height: 48,
                      surfaceTint: palette.surface,
                      tooltip: 'Buscar obras',
                      onTap: onSearchTap,
                      child: Icon(
                        Icons.search_rounded,
                        color: palette.onSurface,
                        size: 22,
                      ),
                    ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 8),
                    IndividualGlassCapsule(
                      isCircle: true,
                      width: 48,
                      height: 48,
                      surfaceTint: palette.surface,
                      child: trailingAction!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
