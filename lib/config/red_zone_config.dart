// =============================================================================
// red_zone_config.dart — Feature 5: Geofenced "Red Zones" Configuration
// =============================================================================
//
// Defines the polygon boundaries for the Helwan service area and the
// surrounding "red zones" where the app is NOT yet available.
//
// HOW IT WORKS:
//   • [serviceAreaPolygon] defines the neighbourhood we actively cover.
//   • [redZonePolygons] defines large rectangles around the service area
//     that represent "out of service" zones.
//   • When the user taps inside a red zone, the map shows a SnackBar
//     saying "Service not yet available in this area."
//
// TO EXPAND COVERAGE:
//   Simply edit [serviceAreaPolygon] to include more coordinates, or
//   remove red zone polygons as you expand.
// =============================================================================

import 'package:google_maps_flutter/google_maps_flutter.dart';

class RedZoneConfig {
  RedZoneConfig._(); // Not instantiable.

  // ── Service Area Boundary (Helwan core neighbourhood) ───────────────────
  //
  // This polygon outlines the area where the app actively tracks ATMs.
  // ATMs outside this boundary won't be covered until the service expands.

  static const List<LatLng> serviceAreaPolygon = [
    LatLng(29.8570, 31.3275), // North-West
    LatLng(29.8570, 31.3410), // North-East
    LatLng(29.8430, 31.3410), // South-East
    LatLng(29.8430, 31.3275), // South-West
  ];

  // ── Red Zone Polygons (uncovered areas surrounding the service zone) ────
  //
  // Four rectangles surrounding the service area, forming a "frame" of
  // red-shaded territory.  Together they tile the visible map area
  // minus the service region.

  /// North red zone – above the service area.
  static const List<LatLng> redZoneNorth = [
    LatLng(29.8700, 31.3100), // NW
    LatLng(29.8700, 31.3550), // NE
    LatLng(29.8570, 31.3550), // SE
    LatLng(29.8570, 31.3100), // SW
  ];

  /// South red zone – below the service area.
  static const List<LatLng> redZoneSouth = [
    LatLng(29.8430, 31.3100), // NW
    LatLng(29.8430, 31.3550), // NE
    LatLng(29.8300, 31.3550), // SE
    LatLng(29.8300, 31.3100), // SW
  ];

  /// West red zone – left of the service area.
  static const List<LatLng> redZoneWest = [
    LatLng(29.8570, 31.3100), // NW
    LatLng(29.8570, 31.3275), // NE
    LatLng(29.8430, 31.3275), // SE
    LatLng(29.8430, 31.3100), // SW
  ];

  /// East red zone – right of the service area.
  static const List<LatLng> redZoneEast = [
    LatLng(29.8570, 31.3410), // NW
    LatLng(29.8570, 31.3550), // NE
    LatLng(29.8430, 31.3550), // SE
    LatLng(29.8430, 31.3410), // SW
  ];

  /// All four red-zone polygons grouped for convenience.
  static const List<List<LatLng>> allRedZones = [
    redZoneNorth,
    redZoneSouth,
    redZoneWest,
    redZoneEast,
  ];

  // ── Helper: point-in-polygon test ───────────────────────────────────────

  /// Returns `true` if [point] is inside any of the red-zone polygons.
  ///
  /// Uses the ray-casting algorithm for point-in-polygon detection.
  static bool isInRedZone(LatLng point) {
    for (final zone in allRedZones) {
      if (_isPointInPolygon(point, zone)) return true;
    }
    return false;
  }

  /// Returns `true` if [point] is inside the active service area.
  static bool isInServiceArea(LatLng point) {
    return _isPointInPolygon(point, serviceAreaPolygon);
  }

  /// Ray-casting algorithm for point-in-polygon detection.
  ///
  /// Shoots a horizontal ray from [point] to the right and counts how many
  /// edges of [polygon] it crosses.  An odd count → inside; even → outside.
  static bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].latitude;
      final yi = polygon[i].longitude;
      final xj = polygon[j].latitude;
      final yj = polygon[j].longitude;

      final intersect = ((yi > point.longitude) != (yj > point.longitude)) &&
          (point.latitude < (xj - xi) * (point.longitude - yi) / (yj - yi) + xi);

      if (intersect) inside = !inside;
      j = i;
    }

    return inside;
  }
}
