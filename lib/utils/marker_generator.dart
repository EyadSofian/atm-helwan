// =============================================================================
// marker_generator.dart — Feature 3: Marker Cache & Generator
// =============================================================================
//
// Pre-generates all four (or five) colour variants of the custom ATM marker
// at app startup, caches them as [BitmapDescriptor]s, and exposes a simple
// lookup: `getMarkerForStatus(AtmStatus) → BitmapDescriptor`.
//
// This avoids re-rendering the Canvas every time a marker is needed
// (which would be expensive for 50+ ATMs on screen).
//
// USAGE:
//   await MarkerGenerator.instance.init(devicePixelRatio);
//   final icon = MarkerGenerator.instance.getMarkerForStatus(AtmStatus.working);
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../atm_model.dart';
import '../widgets/custom_marker_painter.dart';

class MarkerGenerator {
  // Singleton pattern so all screens share the same cache.
  MarkerGenerator._();
  static final MarkerGenerator instance = MarkerGenerator._();

  /// Cached BitmapDescriptors keyed by AtmStatus.
  final Map<AtmStatus, BitmapDescriptor> _cache = {};

  /// Whether [init] has been called and completed.
  bool get isReady => _cache.isNotEmpty;

  // ── Colour mapping (matches the spec exactly) ────────────────────────────
  //
  //   Green  → Working / Has Cash
  //   Red    → Empty / Out of Service
  //   Orange → Crowded
  //   Grey   → Unknown / No recent data
  //
  static const Map<AtmStatus, Color> statusColors = {
    AtmStatus.working: Color(0xFF4CAF50), // Material Green 500
    AtmStatus.empty: Color(0xFFF44336), // Material Red 500
    AtmStatus.crowded: Color(0xFFFF9800), // Material Orange 500
    AtmStatus.broken: Color(0xFFD32F2F), // Material Red 700
    AtmStatus.unknown: Color(0xFF9E9E9E), // Material Grey 500
  };

  /// Generates all marker variants.  Call once during app init (e.g. from
  /// the Splash Screen or MapScreen's [initState]).
  ///
  /// [devicePixelRatio] ensures markers are crisp on high-DPI devices.
  /// Obtain it with `MediaQuery.devicePixelRatioOf(context)`.
  Future<void> init(double devicePixelRatio) async {
    if (_cache.isNotEmpty) return; // Already initialised.

    for (final status in AtmStatus.values) {
      final colour = statusColors[status] ?? Colors.grey;
      _cache[status] = await CustomMarkerPainter.renderToBitmap(
        color: colour,
        devicePixelRatio: devicePixelRatio,
      );
    }

    debugPrint('[MarkerGenerator] Generated ${_cache.length} marker variants.');
  }

  /// Returns the pre-rendered [BitmapDescriptor] for the given status.
  ///
  /// Falls back to the default Google Maps marker if [init] hasn't been
  /// called yet (shouldn't happen in normal usage).
  BitmapDescriptor getMarkerForStatus(AtmStatus status) {
    return _cache[status] ?? BitmapDescriptor.defaultMarker;
  }
}
