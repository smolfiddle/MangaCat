import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'constants.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.12),
      ),
      child: CustomPaint(
        painter: PawPainter(color: AppColors.accent, spanFraction: 0.58),
      ),
    );
  }
}

class PawPainter extends CustomPainter {
  PawPainter({required this.color, this.spanFraction = 0.58});

  final Color color;
  final double spanFraction;

  static const List<(double, double, double, double, double, double)> _pads =
      <(double, double, double, double, double, double)>[
    (50.0, 66.0, 24.0, 18.0, 0.0, 2.7),
    (24.5, 28.5, 11.0, 12.5, -20.0, 2.5),
    (50.0, 21.5, 12.0, 14.5, 0.0, 2.5),
    (75.5, 28.5, 11.0, 12.5, 20.0, 2.5),
  ];

  static List<Offset> _padPoints(
    double cx,
    double cy,
    double a,
    double b,
    double rotDeg,
    double n,
  ) {
    final rot = rotDeg * math.pi / 180.0;
    final cosR = math.cos(rot);
    final sinR = math.sin(rot);
    const steps = 180;
    final points = <Offset>[];
    for (var i = 0; i < steps; i++) {
      final t = 2.0 * math.pi * i / steps;
      final ct = math.cos(t);
      final st = math.sin(t);
      final xr = a *
          (ct < 0 ? -1.0 : 1.0) *
          math.pow(ct.abs(), 2.0 / n).toDouble();
      final yr = b *
          (st < 0 ? -1.0 : 1.0) *
          math.pow(st.abs(), 2.0 / n).toDouble();
      points.add(Offset(cx + xr * cosR - yr * sinR, cy + xr * sinR + yr * cosR));
    }
    return points;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final polygons = <List<Offset>>[];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final pad in _pads) {
      final points = _padPoints(pad.$1, pad.$2, pad.$3, pad.$4, pad.$5, pad.$6);
      for (final point in points) {
        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
      }
      polygons.add(points);
    }

    final span = math.max(maxX - minX, maxY - minY);
    final scale = size.shortestSide * spanFraction / span;
    final dx = (size.width - (minX + maxX) * scale) / 2.0;
    final dy = (size.height - (minY + maxY) * scale) / 2.0;

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    for (final points in polygons) {
      final path = Path()
        ..moveTo(points.first.dx * scale + dx, points.first.dy * scale + dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx * scale + dx, point.dy * scale + dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PawPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.spanFraction != spanFraction;
}

class DirtyDot extends StatelessWidget {
  const DirtyDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Unsaved changes',
      child: Tooltip(
        message: 'Unsaved changes',
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
