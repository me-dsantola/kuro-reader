import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/kuro_cosmetics_service.dart';

class KuroAttachmentAnchors {
  final Offset top, neck, center;
  final double width, angle, rotation, radius;
  const KuroAttachmentAnchors(
    this.top,
    this.neck,
    this.center,
    this.width,
    this.angle,
    this.rotation,
    this.radius,
  );
  factory KuroAttachmentAnchors.fromBody(List<double> p) {
    final center = Offset(
      List.generate(64, (i) => p[i * 2]).reduce((a, b) => a + b) / 64,
      List.generate(64, (i) => p[i * 2 + 1]).reduce((a, b) => a + b) / 64,
    );
    Offset at(double index) {
      final i = index.floor() % 64, j = (i + 1) % 64;
      return Offset.lerp(
        Offset(p[i * 2], p[i * 2 + 1]),
        Offset(p[j * 2], p[j * 2 + 1]),
        index - index.floor(),
      )!;
    }

    final left = at(64 * 5 / 12), right = at(64 / 12), top = at(48);
    final direction = right - left;
    return KuroAttachmentAnchors(
      top,
      (left + right) / 2,
      center,
      direction.distance,
      math.atan2(direction.dy, direction.dx),
      math.atan2(p[1] - center.dy, p[0] - center.dx),
      List.generate(
        64,
        (i) => (Offset(p[i * 2], p[i * 2 + 1]) - center).distance,
      ).reduce(math.max),
    );
  }
}

Color kuroItemColor(Map<String, dynamic> item) => Color(
  int.parse(
    ((item['color'] ?? item['accent']) as String).replaceFirst('#', 'FF'),
    radix: 16,
  ),
);
void paintKuroAccessories(
  Canvas canvas,
  Path body,
  List<double> points,
  double visibility,
  Map<String, String> equipment,
  KuroCatalog? catalog,
  double time, {
  required bool behind,
}) {
  if (catalog == null || visibility <= .001) return;
  final a = KuroAttachmentAnchors.fromBody(points);
  final aura = catalog.item(equipment['aura'] ?? '');
  if (behind) {
    if (aura != null) {
      final c = kuroItemColor(aura);
      for (final pair in [
        [18.0, .08],
        [9.0, .16],
        [2.0, .7],
      ]) {
        canvas.drawPath(
          body,
          Paint()
            ..color = c.withValues(alpha: pair[1] * visibility)
            ..style = PaintingStyle.stroke
            ..strokeWidth = pair[0],
        );
      }
    }
    return;
  }
  canvas.saveLayer(
    const Rect.fromLTWH(-240, -240, 480, 480),
    Paint()..color = Colors.white.withValues(alpha: visibility.clamp(0.0, 1.0)),
  );
  final scarf = catalog.item(equipment['scarf'] ?? '');
  if (scarf != null) {
    canvas.save();
    canvas.translate(a.neck.dx, a.neck.dy);
    canvas.rotate(a.angle);
    canvas.scale(a.width / 172);
    final paint = Paint()..color = kuroItemColor(scarf);
    canvas.drawPath(
      Path()
        ..moveTo(-86, -9)
        ..quadraticBezierTo(0, 13, 86, -9)
        ..lineTo(84, 8)
        ..quadraticBezierTo(0, 29, -84, 8)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(44, 13)
        ..lineTo(64, 10)
        ..lineTo(72, 59)
        ..lineTo(50, 64)
        ..close(),
      paint,
    );
    canvas.drawLine(
      const Offset(49, 53),
      const Offset(70, 48),
      Paint()
        ..color = const Color(0xFFFFE0D9)
        ..strokeWidth = 3,
    );
    canvas.restore();
  }
  final hat = catalog.item(equipment['hat'] ?? '');
  if (hat != null) {
    canvas.save();
    canvas.translate(a.top.dx, a.top.dy + 3);
    canvas.rotate(a.rotation);
    canvas.scale(
      (a.width / 172).clamp(.5, 1.1) * (hat['design'] == 'santa' ? 0.85 : 0.6),
    );
    final paint = Paint()..color = kuroItemColor(hat);
    if (hat['design'] == 'santa') {
      canvas.drawPath(
        Path()
          ..moveTo(-60, 2)
          ..quadraticBezierTo(-45, -64, 8, -67)
          ..quadraticBezierTo(51, -71, 63, -19)
          ..lineTo(45, -15)
          ..quadraticBezierTo(31, -40, 15, -35)
          ..quadraticBezierTo(-8, -30, -25, 7)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(-63, 1)
          ..quadraticBezierTo(0, -17, 55, 2)
          ..lineTo(56, 19)
          ..quadraticBezierTo(0, 4, -62, 18)
          ..close(),
        Paint()..color = const Color(0xFFFFF2FD),
      );
      canvas.drawCircle(
        const Offset(59, -13),
        12,
        Paint()..color = const Color(0xFFFFF2FD),
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-48, 4)
          ..lineTo(-11, -78)
          ..quadraticBezierTo(4, -96, 30, -67)
          ..lineTo(13, -55)
          ..lineTo(43, 3)
          ..close(),
        paint,
      );
      canvas.drawOval(const Rect.fromLTWH(-67, -6, 132, 30), paint);
      canvas.drawLine(
        const Offset(-28, -8),
        const Offset(30, -8),
        Paint()
          ..color = const Color(0xFFE3B366)
          ..strokeWidth = 8,
      );
    }
    canvas.restore();
  }
  final object = catalog.item(equipment['floating'] ?? '');
  if (object != null) {
    canvas.save();
    canvas.translate(
      a.center.dx + math.cos(time * .7) * (a.radius + 24),
      a.center.dy + math.sin(time * .7) * (a.radius + 18),
    );
    canvas.rotate(math.sin(time) * .14);
    final paint = Paint()..color = kuroItemColor(object);
    if (object['design'] == 'star') {
      final p = Path();
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5, r = i.isEven ? 17.0 : 8.0;
        final x = math.cos(angle) * r, y = math.sin(angle) * r;
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      canvas.drawPath(p..close(), paint);
    } else if (object['design'] == 'book') {
      canvas.drawPath(
        Path()
          ..moveTo(-22, -16)
          ..quadraticBezierTo(-8, -19, 0, -11)
          ..quadraticBezierTo(8, -19, 22, -16)
          ..lineTo(22, 17)
          ..quadraticBezierTo(9, 14, 0, 22)
          ..quadraticBezierTo(-9, 14, -22, 17)
          ..close(),
        paint,
      );
      canvas.drawLine(
        const Offset(0, -11),
        const Offset(0, 22),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.5,
      );
    } else {
      canvas.drawOval(const Rect.fromLTWH(-20, -16, 40, 32), paint);
      canvas.drawLine(
        const Offset(0, -14),
        const Offset(2, -25),
        Paint()
          ..color = const Color(0xFF73C9A1)
          ..strokeWidth = 5,
      );
      canvas.drawCircle(
        const Offset(-7, -2),
        3,
        Paint()..color = const Color(0xFF322043),
      );
      canvas.drawCircle(
        const Offset(7, -2),
        3,
        Paint()..color = const Color(0xFF322043),
      );
    }
    canvas.restore();
  }
  canvas.restore();
}
