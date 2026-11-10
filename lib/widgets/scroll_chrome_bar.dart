import 'package:flutter/material.dart';

class ScrollChromeBar extends StatelessWidget {
  final bool visible;
  final Widget child;
  const ScrollChromeBar({
    super.key,
    required this.visible,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: visible ? 1 : 0,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !visible,
            child: ExcludeSemantics(excluding: !visible, child: child),
          ),
        ),
      ),
    );
  }
}
