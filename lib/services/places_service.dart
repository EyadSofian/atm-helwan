// =============================================================================
// places_service.dart — Google Places API Integration
// =============================================================================
//
// Fetches real ATM locations from the Google Places API (Nearby Search)
// within the Helwan service zone and writes them to Firestore.
//
// HOW IT WORKS:
//   1. Calls the Places API "Nearby Search" endpoint with type='atm'
//      centred on the Helwan service area.
//   2. Parses the JSON response to extract name, lat, lng, and placeId.
//   3. Filters results to only include ATMs within the green service zone.
//   4. Returns a list of parsed ATM data maps.
//
// API KEY:
//   The key is read from `lib/config/secrets.dart` → Secrets.googleMapsApiKey.
//   Make sure you have the "Places API" enabled in your Google Cloud Console
//   for this key.
//
// RATE LIMITS:
//   The Nearby Search API returns up to 20 results per request.  If a
//   `next_page_token` is present in the response, this service automatically
//   fetches the next page (up to 3 pages = 60 results max).
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/secrets.dart';
import '../config/red_zone_config.dart';

class PlacesService {
  /// The Google Places API key.
  /// ─────────────────────────────────────────────────────────────────────────
  /// YOUR API KEY IS READ FROM: lib/config/secrets.dart
  ///
  ///   class Secrets {
  ///     static const String googleMapsApiKey = 'YOUR_KEY_HERE';
  ///   }
  ///
  /// Make sure "Places API" is ENABLED in your Google Cloud Console.
  /// ─────────────────────────────────────────────────────────────────────────
  static const String _apiKey = Secrets.googleMapsApiKey;

  /// Base URL for the Places API Nearby Search.
  static const String _nearbySearchUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  /// Centre of the Helwan service area (used as the search origin).
  static const double _centerLat = 29.8500;
  static const double _centerLng = 31.3342;

  /// Search radius in metres — covers the entire green service zone.
  /// The service zone is roughly 1.5 km × 1.5 km, so 1000m radius from
  /// the centre covers it well.
  static const int _searchRadiusMeters = 1500;

  // ── Main fetch method ──────────────────────────────────────────────────

  /// Fetches all ATMs from the Google Places API within the service zone.
  ///
  /// Returns a list of maps with keys:
  ///   - 'name'    : String (ATM / bank name)
  ///   - 'lat'     : double
  ///   - 'lng'     : double
  ///   - 'placeId' : String (Google Place ID, useful for future details)
  ///   - 'address' : String (vicinity / address)
  ///
  /// Returns an empty list if the API call fails or no ATMs are found.
  Future<List<Map<String, dynamic>>> fetchAtmsInServiceZone() async {
    final allResults = <Map<String, dynamic>>[];
    String? nextPageToken;

    try {
      // Fetch up to 3 pages (60 results max from Nearby Search).
      for (int page = 0; page < 3; page++) {
        final uri = _buildUri(nextPageToken);
        debugPrint('[PlacesService] Fetching page ${page + 1}: $uri');

        final response = await http.get(uri);

        if (response.statusCode != 200) {
          debugPrint('[PlacesService] HTTP error: ${response.statusCode}');
          break;
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final status = json['status'] as String?;

        if (status != 'OK' && status != 'ZERO_RESULTS') {
          debugPrint('[PlacesService] API error: $status — ${json['error_message'] ?? ''}');
          break;
        }

        final results = json['results'] as List<dynamic>? ?? [];
        debugPrint('[PlacesService] Page ${page + 1}: ${results.length} results');

        for (final place in results) {
          final parsed = _parsePlace(place as Map<String, dynamic>);
          if (parsed != null) {
            allResults.add(parsed);
          }
        }

        // Check for next page.
        nextPageToken = json['next_page_token'] as String?;
        if (nextPageToken == null) break;

        // Google requires a short delay before using the next_page_token.
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('[PlacesService] Fetch error: $e');
    }

    debugPrint('[PlacesService] Total ATMs found in service zone: ${allResults.length}');
    return allResults;
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Builds the API request URI, optionally with a pagination token.
  Uri _buildUri(String? pageToken) {
    final params = <String, String>{
      'location': '$_centerLat,$_centerLng',
      'radius': '$_searchRadiusMeters',
      'type': 'atm',
      'key': _apiKey,
    };

    if (pageToken != null) {
      params['pagetoken'] = pageToken;
    }

    return Uri.parse(_nearbySearchUrl).replace(queryParameters: params);
  }

  /// Parses a single Places API result into our ATM data format.
  ///
  /// Returns `null` if the place is outside the green service zone
  /// (we only want ATMs within our coverage area).
  Map<String, dynamic>? _parsePlace(Map<String, dynamic> place) {
    final geometry = place['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;

    if (location == null) return null;

    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();

    if (lat == null || lng == null) return null;

    // ── Filter: only keep ATMs inside the green service zone ──────────
    final point = LatLng(lat, lng);
    if (!RedZoneConfig.isInServiceArea(point)) {
      debugPrint('[PlacesService] Skipping out-of-zone ATM: ${place['name']}');
      return null;
    }

    return {
      'name': (place['name'] as String?) ?? 'ATM',
      'lat': lat,
      'lng': lng,
      'placeId': (place['place_id'] as String?) ?? '',
      'address': (place['vicinity'] as String?) ?? '',
    };
  }
}
