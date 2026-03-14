// =============================================================================
// custom_marker_painter.dart — Feature 3: Custom Brand Markers
// =============================================================================
//
// Uses Flutter's Canvas / CustomPainter API to draw an ATM-branded map pin
// that replaces the default Google Maps marker.
//
// The marker is a teardrop-shaped pin with:
//   • A filled body whose colour changes based on ATM status.
//   • A white ATM icon in the centre.
//   • A subtle shadow for depth.
//
// The painter is status-agnostic — it receives a [Color] and draws.
// The [MarkerGenerator] class (see marker_generator.dart) is responsible
// for creating BitmapDescriptor instances for each status colour.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Draws a custom ATM marker pin on a Canvas.
///
/// The pin is 80×100 logical pixels.  Adjust [kMarkerWidth] and
/// [kMarkerHeight] if you'd like a larger or smaller marker.
class CustomMarkerPainter extends CustomPainter {
  /// The fill colour of the pin body (green, red, orange, grey, etc.).
  final Color color;

  /// The icon to paint inside the pin (defaults to ATM icon).
  final IconData icon;

  static const double kMarkerWidth = 80;
  static const double kMarkerHeight = 100;

  const CustomMarkerPainter({
    required this.color,
    this.icon = Icons.atm_rounded,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // ── 1. Shadow ──────────────────────────────────────────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(
      Offset(w / 2, h - 8),
      8,
      shadowPaint,
    );

    // ── 2. Pin body (teardrop shape) ───────────────────────────────────────
    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final double circleRadius = w * 0.40;
    final double circleY = h * 0.38;
    final Offset center = Offset(w / 2, circleY);

    // Start from the bottom tip of the teardrop.
    path.moveTo(w / 2, h - 4);

    // Left curve from tip up to the circle.
    path.quadraticBezierTo(
      w * 0.05,
      circleY + circleRadius * 0.3,
      center.dx - circleRadius,
      circleY,
    );

    // Arc around the top (full half-circle).
    path.arcTo(
      Rect.fromCircle(center: center, radius: circleRadius),
      math.pi, // start angle
      -math.pi, // sweep (counter-clockwise full semi-circle)
      false,
    );

    // Right curve from circle back down to the tip.
    path.quadraticBezierTo(
      w * 0.95,
      circleY + circleRadius * 0.3,
      w / 2,
      h - 4,
    );

    path.close();
    canvas.drawPath(path, bodyPaint);

    // ── 3. White circle background for the icon ───────────────────────────
    final iconBgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, circleRadius * 0.65, iconBgPaint);

    // ── 4. ATM icon ───────────────────────────────────────────────────────
    final iconSize = circleRadius * 0.85;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomMarkerPainter oldDelegate) =>
      color != oldDelegate.color || icon != oldDelegate.icon;

  // ── Static helper: render to BitmapDescriptor ────────────────────────────

  /// Renders this painter into a [BitmapDescriptor] suitable for use as a
  /// Google Maps marker icon.
  ///
  /// [devicePixelRatio] should be obtained from `MediaQuery.devicePixelRatioOf`
  /// so markers look crisp on high-DPI screens.
  static Future<BitmapDescriptor> renderToBitmap({
    required Color color,
    IconData icon = Icons.atm_rounded,
    double devicePixelRatio = 2.0,
  }) async {
    final double width = CustomMarkerPainter.kMarkerWidth * devicePixelRatio;
    final double height = CustomMarkerPainter.kMarkerHeight * devicePixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width, height),
    );

    final painter = CustomMarkerPainter(color: color, icon: icon);
    painter.paint(canvas, Size(width, height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      // Fallback to default marker if rendering fails.
      return BitmapDescriptor.defaultMarker;
    }

    return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  }
}
