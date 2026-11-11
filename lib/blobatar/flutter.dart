/// The Flutter widget layer of the blobatar SDK.
///
/// ```dart
/// import 'package:blobatar/flutter.dart';
///
/// AnimatedBlobatar(name: 'alain@example.com', size: 48)
/// ```
///
/// The widgets paint the deterministic generation-2 layout through
/// `dart:ui` primitives — the same math the parity fixture pins against the
/// TypeScript core. For the pure, Flutter-independent engine (hash, traits,
/// palette, layout), import `package:blobatar/blobatar.dart` instead.
library;

export 'blobatar.dart'
    show
        Backdrop,
        BackdropGeometry,
        BlobatarOptions,
        Palette,
        Pose,
        MotionFrame,
        MotionSeeds,
        MotionWrap,
        motionAt,
        motionSeedsFor,
        Expression,
        idle,
        happy,
        sad,
        mad,
        surprised,
        wink,
        sleepy,
        smug,
        unsure,
        scared,
        love,
        shy,
        sick,
        thinking,
        expressions;

export 'src/flutter/animated_painter.dart' show AnimatedBlobatarPainter;
export 'src/flutter/animated_renderer.dart'
    show AnimatedBlobatarFrame, AnimatedBlobatarRenderer;
export 'src/flutter/animated_widget.dart'
    show AnimatedBlobatar, BlobatarAnimation;
export 'src/flutter/painter.dart' show BlobatarPainter;
export 'src/flutter/renderer.dart' show BlobatarRenderer;
export 'src/flutter/widget.dart' show Blobatar;
