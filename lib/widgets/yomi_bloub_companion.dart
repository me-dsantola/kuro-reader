import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/device_state_service.dart';

enum BloubContext { profile, welcome, library, reader, complete, empty }

/// Cached vector poses sampled from the MIT Bloub engine. No web view or video.
class BloubAtlas {
  final Map<String, dynamic> data;
  BloubAtlas._(this.data);
  static Future<BloubAtlas>? _loading;
  static BloubAtlas? _cached;
  static Future<BloubAtlas> load() => _loading ??= rootBundle
      .loadString('assets/mascot/bloub-motion.json')
      .then((s) => compute(_decodeAtlas, s))
      .then((data) => _cached = BloubAtlas._(data));
  final Map<String, List<_Frame>> _clips = {};
  final Map<String, _Frame> _rests = {};
  @visibleForTesting
  List<double> sampleBody(String state, double time, String shape) =>
      _sample(state, time, shape, 'attentif').body;
  _Frame _rest(String shape, String expression) {
    final key = '$shape/$expression';
    return _rests.putIfAbsent(key, () {
      final shapes = data['rest'] as Map<String, dynamic>;
      final expressions =
          (shapes[shape] ?? shapes['goutte']) as Map<String, dynamic>;
      return _Frame.fromJson(
        (expressions[expression] ?? expressions['attentif'])
            as Map<String, dynamic>,
      );
    });
  }

  _Frame _sample(String state, double time, String shape, String expression) {
    final frames = _clips.putIfAbsent(
      state,
      () => ((data['clips'] as Map<String, dynamic>)[state] as List)
          .map((f) => _Frame.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
    final t = (time * (data['fps'] as num))
        .clamp(0, frames.length - 1)
        .toDouble();
    final i = t.floor();
    final frame = _Frame.lerp(
      frames[i],
      frames[math.min(i + 1, frames.length - 1)],
      t - i,
    );
    // The clip supplies motion, never the user's body geometry.
    final profiles = data['profiles'] as Map<String, dynamic>;
    final radii = _numbers(profiles[shape] ?? profiles['goutte']);
    final sil = frame.silhouette!;
    final cr = math.cos(sil[0]), sr = math.sin(sil[0]);
    final body = <double>[];
    for (var i = 0; i < radii.length; i++) {
      final angle = i / radii.length * math.pi * 2;
      final x = radii[i] * math.cos(angle), y = radii[i] * math.sin(angle);
      body.addAll([
        (sil[1] + (x * cr - y * sr) * sil[3]) * 100,
        (sil[2] + (x * sr + y * cr) * sil[4]) * 100,
      ]);
    }
    final fits =
        (data['eyeFit'] as Map<String, dynamic>)[shape] ??
        (data['eyeFit'] as Map<String, dynamic>)['goutte'];
    final byState =
        (fits as Map<String, dynamic>)[state] as Map<String, dynamic>;
    final offset = _numbers(byState[expression] ?? byState['attentif']);
    final eyes = frame.eyes.map((eye) {
      final e = List<double>.from(eye);
      final fit = _radius(radii, math.atan2(e[10], e[9]) - sil[0]);
      e[6] = e[9] * fit + e[11] + offset[0];
      e[7] = e[10] * fit + e[12] + offset[1];
      return e;
    }).toList();
    List<double>? retarget(List<double>? point) {
      if (point == null) return null;
      final offX = frame.eyes.isEmpty ? 0.0 : frame.eyes.first[11];
      final offY = frame.eyes.isEmpty ? 0.0 : frame.eyes.first[12];
      final x = point[0] - offX, y = point[1] - offY;
      final angle = math.atan2(y, x) - sil[0];
      final original = _radius(_numbers(profiles['goutte']), angle);
      final ratio = _radius(radii, angle) / original;
      return [offX + x * ratio, offY + y * ratio, point[2]];
    }

    return _Frame(
      body,
      frame.alpha,
      eyes,
      frame.arcs,
      frame.dots,
      frame.behind,
      retarget(frame.notification),
      retarget(frame.notch),
      sil,
    );
  }
}

double _radius(List<double> radii, double angle) {
  final phase = ((angle / (2 * math.pi)) % 1) * radii.length;
  final index = phase.floor();
  return _mix(
    radii[index % radii.length],
    radii[(index + 1) % radii.length],
    phase - index,
  );
}

Map<String, dynamic> _decodeAtlas(String source) =>
    jsonDecode(source) as Map<String, dynamic>;

List<double> _numbers(dynamic value) =>
    (value as List).map((v) => (v as num).toDouble()).toList();
List<List<double>> _rows(dynamic value) =>
    (value as List).map(_numbers).toList();
double _mix(double a, double b, double t) => a + (b - a) * t;
List<double> _blend(List<double> a, List<double> b, double t) =>
    List.generate(b.length, (i) => _mix(i < a.length ? a[i] : b[i], b[i], t));
List<List<double>> _blendRows(
  List<List<double>> a,
  List<List<double>> b,
  double t,
  int opacity,
) => List.generate(math.max(a.length, b.length), (i) {
  final left = i < a.length ? a[i] : _invisible(b[i], opacity);
  final right = i < b.length ? b[i] : _invisible(a[i], opacity);
  return _blend(left, right, t);
});
List<double> _invisible(List<double> a, int opacity) =>
    List<double>.from(a)..[opacity] = 0;

class _Frame {
  final List<double> body;
  final double alpha;
  final List<List<double>> eyes, arcs, dots;
  final bool behind;
  final List<double>? notification, notch;
  final List<double>? silhouette;
  const _Frame(
    this.body,
    this.alpha,
    this.eyes,
    this.arcs,
    this.dots,
    this.behind,
    this.notification,
    this.notch, [
    this.silhouette,
  ]);
  factory _Frame.fromJson(Map<String, dynamic> f) => _Frame(
    _numbers(f['b']),
    (f['a'] as num).toDouble(),
    _rows(f['e']),
    _rows(f['r']),
    _rows(f['d']),
    f['z'] as bool,
    f['n'] == null ? null : _numbers(f['n']),
    f['h'] == null ? null : _numbers(f['h']),
    _numbers(f['s']),
  );
  static List<double>? _circle(List<double>? a, List<double>? b, double t) {
    if (a == null && b == null) return null;
    return _blend(a ?? [b![0], b[1], 0], b ?? [a![0], a[1], 0], t);
  }

  static _Frame lerp(_Frame a, _Frame b, double t) => _Frame(
    _blend(a.body, b.body, t),
    _mix(a.alpha, b.alpha, t),
    _blendRows(a.eyes, b.eyes, t, 8),
    _blendRows(a.arcs, b.arcs, t, 10),
    _blendRows(a.dots, b.dots, t, 3),
    t < .5 ? a.behind : b.behind,
    _circle(a.notification, b.notification, t),
    _circle(a.notch, b.notch, t),
    a.silhouette == null || b.silhouette == null
        ? null
        : _blend(a.silhouette!, b.silhouette!, t),
  );
}

class _RepaintSignal extends ChangeNotifier {
  void tick() => notifyListeners();
}

class YomiBloubCompanion extends StatefulWidget {
  final double size;
  final BloubContext context;
  final String shape, expression, label;
  final Color? accent;
  final bool animated, interactive;
  const YomiBloubCompanion({
    super.key,
    this.size = 80,
    this.context = BloubContext.profile,
    this.shape = 'goutte',
    this.expression = 'attentif',
    this.label = 'Kuro, seu companheiro de leitura',
    this.accent,
    this.animated = true,
    this.interactive = true,
  });
  @override
  State<YomiBloubCompanion> createState() => _YomiBloubCompanionState();
}

class _YomiBloubCompanionState extends State<YomiBloubCompanion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  final _RepaintSignal _repaint = _RepaintSignal();
  BloubAtlas? _atlas;
  _Frame? _current, _origin;
  String _state = 'idle';
  double _time = 0,
      _since = 0,
      _blendAt = 0,
      _last = 0,
      _returnAt = double.infinity,
      _gestureAt = 26;
  int _gesture = 0;
  bool _foreground = true, _reduced = false;
  ScrollPosition? _scroll;
  bool _scrollPending = false;
  Color _colorFrom = const Color(0xFF8C70FF);
  double _colorAt = -1;
  Color get _target => widget.accent ?? const Color(0xFF8C70FF);
  Color get _color => Color.lerp(
    _colorFrom,
    _target,
    Curves.easeInOut.transform(((_time - _colorAt) / .65).clamp(0.0, 1.0)),
  )!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_advance);
    DeviceStateService.instance.addListener(_sync);
    if (BloubAtlas._cached != null) {
      _atlas = BloubAtlas._cached;
      _current = _atlas!._rest(widget.shape, widget.expression);
      _opening();
    } else {
      BloubAtlas.load()
          .then((atlas) {
            if (!mounted) return;
            setState(() {
              _atlas = atlas;
              _current = atlas._rest(widget.shape, widget.expression);
            });
            _opening();
            _sync();
          })
          .catchError((Object error) {
            debugPrint('Mascote indisponível: $error');
          });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (next != _scroll) {
      _scroll?.removeListener(_scrollChanged);
      _scroll = next;
      _scroll?.addListener(_scrollChanged);
    }
    _reduced = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _scrollChanged() {
    if (_scrollPending) return;
    _scrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (mounted) _sync();
    });
  }

  @override
  void didUpdateWidget(covariant YomiBloubCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accent != widget.accent) {
      _colorFrom = oldWidget.accent ?? const Color(0xFF8C70FF);
      _colorAt = _time;
    }
    if (oldWidget.context != widget.context) _opening();
    if (oldWidget.shape != widget.shape ||
        oldWidget.expression != widget.expression) {
      _origin = _current;
      _blendAt = _time;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  bool get _onScreen {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return true;
    return (box.localToGlobal(Offset.zero) & box.size).overlaps(
      Offset.zero & MediaQuery.sizeOf(context),
    );
  }

  bool get _enabled =>
      _atlas != null &&
      widget.animated &&
      widget.size >= 48 &&
      !_reduced &&
      !DeviceStateService.instance.value.reduceEffects &&
      _foreground &&
      TickerMode.of(context) &&
      _onScreen;
  void _sync() {
    if (!mounted) return;
    if (_enabled) {
      if (!_clock.isAnimating) {
        _last = 0;
        _clock.repeat();
      }
    } else {
      _clock.stop();
      _last = 0;
      _colorFrom = _target;
      _colorAt = _time - 1;
      // Settle a requested pose without running a hidden/reduced-motion loop.
      if (_atlas != null) {
        if (_time - _blendAt < .65) _time = _blendAt + .65;
        _current = _sample(_time);
        _repaint.tick();
      }
    }
  }

  void _opening() {
    final state = switch (widget.context) {
      BloubContext.profile => 'orbit',
      BloubContext.welcome => 'wink',
      BloubContext.library => 'thinking',
      BloubContext.complete => 'burst',
      BloubContext.empty => 'wide',
      BloubContext.reader => 'idle',
    };
    _change(state);
    _returnAt = state == 'idle'
        ? double.infinity
        : _time + (state == 'burst' ? 3.6 : 2.8);
    _gestureAt = _time + 28;
  }

  void _change(String state) {
    _origin = _current;
    _state = state;
    _since = _time;
    _blendAt = _time;
    if (_atlas != null) {
      _current = _sample(_time);
      _repaint.tick();
    }
  }

  _Frame _sample(double now) {
    final local = math.max(0.0, now - _since);
    var target = _state == 'idle'
        ? _atlas!._rest(widget.shape, widget.expression)
        : _atlas!._sample(_state, local, widget.shape, widget.expression);
    if (_state == 'idle' && widget.animated && !_reduced) {
      final cycle = now % 4.8;
      final blink = cycle > 4.5
          ? 1 - math.sin((cycle - 4.5) / .3 * math.pi) * .96
          : 1.0;
      final eyes = target.eyes.map((eye) {
        final e = List<double>.from(eye);
        e[1] *= blink;
        e[6] += math.sin(now * .6) * 1.2;
        return e;
      }).toList();
      target = _Frame(
        target.body,
        target.alpha,
        eyes,
        target.arcs,
        target.dots,
        target.behind,
        target.notification,
        target.notch,
      );
    }
    final k = Curves.easeInOutCubic.transform(
      ((now - _blendAt) / .65).clamp(0.0, 1.0),
    );
    return _origin != null && k < 1 ? _Frame.lerp(_origin!, target, k) : target;
  }

  void _advance() {
    if (!_enabled) {
      _sync();
      return;
    }
    final elapsed = (_clock.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
    final dt = _last == 0 ? 0.0 : (elapsed - _last).clamp(0.0, .064);
    _last = elapsed;
    _time += dt * .9;
    if (_time >= _returnAt) {
      _returnAt = double.infinity;
      _change('idle');
    }
    if (widget.context != BloubContext.reader && _time >= _gestureAt) {
      _change(['wink', 'thinking', 'wide'][_gesture++ % 3]);
      _returnAt = _time + 2.3;
      _gestureAt = _time + 28 + (_gesture % 3) * 7;
    }
    _current = _sample(_time);
    _repaint.tick();
  }

  void _tap() {
    _change('wink');
    _returnAt = _time + 2;
    _gestureAt = _time + 28;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceStateService.instance.removeListener(_sync);
    _scroll?.removeListener(_scrollChanged);
    _clock.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    button: widget.interactive,
    child: GestureDetector(
      onTap: widget.interactive ? _tap : null,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _BloubPainter(
            frame: () => _current,
            color: () => _color,
            paper: Theme.of(context).scaffoldBackgroundColor,
            repaint: _repaint,
          ),
        ),
      ),
    ),
  );
}

class _BloubPainter extends CustomPainter {
  final _Frame? Function() frame;
  final Color Function() color;
  final Color paper;
  _BloubPainter({
    required this.frame,
    required this.color,
    required this.paper,
    required Listenable repaint,
  }) : super(repaint: repaint);
  Path _body(List<double> p) {
    final path = Path();
    final n = p.length ~/ 2;
    Offset point(int i) {
      final j = (i % n + n) % n;
      return Offset(p[j * 2], p[j * 2 + 1]);
    }

    path.moveTo(p[0], p[1]);
    for (var i = 0; i < n; i++) {
      final a = point(i - 1), b = point(i), c = point(i + 1), d = point(i + 2);
      final c1 = b + (c - a) / 6, c2 = c - (d - b) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, c.dx, c.dy);
    }
    return path..close();
  }

  void _rings(Canvas canvas, List<List<double>> arcs, bool back, Color c) {
    for (final a in arcs) {
      final path = Path();
      bool? previous;
      for (var i = 0; i <= 72; i++) {
        final theta =
            a[4] + a[9] * a[3] * 2 * math.pi + a[5] * 2 * math.pi * (i / 72);
        final ct = math.cos(theta),
            st = math.sin(theta),
            cu = math.cos(a[2]),
            su = math.sin(a[2]);
        final behind = st < 0;
        final x = (a[0] * (ct * cu - st * su * a[1]) + a[7]) * 100;
        final y = (a[0] * (ct * su + st * cu * a[1]) + a[8]) * 100;
        if (behind == back) {
          if (previous != behind) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        previous = behind;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(
            c,
            const Color(0xFF52E3F5),
            .45,
          )!.withValues(alpha: a[10].clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = a[6] * 100,
      );
    }
  }

  void _dots(Canvas canvas, _Frame f, Color c) {
    for (final d in f.dots) {
      if (d.every((v) => v.isFinite)) {
        canvas.drawCircle(
          Offset(d[0], d[1]),
          math.max(0, d[2]),
          Paint()
            ..color = Color.lerp(
              paper,
              c,
              d[4].clamp(0.0, 1.0),
            )!.withValues(alpha: d[3].clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame();
    final c = color();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 316);
    if (f == null) {
      canvas.drawCircle(Offset.zero, 80, Paint()..color = c);
      canvas.restore();
      return;
    }
    _rings(canvas, f.arcs, true, c);
    if (f.behind) _dots(canvas, f, c);
    final body = _body(f.body);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(c, const Color(0xFF52E3F5), .65)!,
            c,
            Color.lerp(c, const Color(0xFF20234F), .6)!,
          ],
        ).createShader(const Rect.fromLTWH(-100, -100, 200, 200))
        ..color = Colors.white.withValues(alpha: f.alpha.clamp(0.0, 1.0)),
    );
    canvas.save();
    canvas.clipPath(body);
    for (final e in f.eyes) {
      canvas.save();
      canvas.transform(
        Float64List.fromList([
          e[2],
          e[3],
          0,
          0,
          e[4],
          e[5],
          0,
          0,
          0,
          0,
          1,
          0,
          e[6],
          e[7],
          0,
          1,
        ]),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: math.max(.01, e[0]),
            height: math.max(.01, e[1]),
          ),
          Radius.circular(math.min(e[0], e[1]) / 2),
        ),
        Paint()
          ..color = paper.withValues(alpha: (e[8] * f.alpha).clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
    if (f.notch != null) {
      canvas.drawCircle(
        Offset(f.notch![0], f.notch![1]),
        math.max(0, f.notch![2]),
        Paint()..color = paper,
      );
    }
    canvas.restore();
    if (!f.behind) _dots(canvas, f, c);
    if (f.notification != null) {
      canvas.drawCircle(
        Offset(f.notification![0], f.notification![1]),
        math.max(0, f.notification![2]),
        Paint()..color = const Color(0xFF52E3F5),
      );
    }
    _rings(canvas, f.arcs, false, c);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BloubPainter oldDelegate) => true;
}
