// =============================================================================
// seed_service.dart — ATM Seeding (Google Places API + JSON fallback)
// =============================================================================
//
// Responsible for populating the Firestore "atms" collection with real ATM
// locations.  On first run it:
//
//   1. Tries to fetch real ATMs from the Google Places API (Nearby Search).
//   2. If the API call succeeds and returns results, writes those to Firestore.
//   3. If the API fails or returns zero results, falls back to the local
//      JSON asset (assets/atm_seed_data.json) as a safety net.
//
// On subsequent runs, if ATMs already exist in Firestore, the seeding is
// skipped entirely.
//
// HOW TO FORCE A RE-SEED:
//   Delete all documents in the "atms" Firestore collection, then restart
//   the app.  The seed will run again.
// =============================================================================

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../atm_model.dart';
import 'places_service.dart';

class SeedService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _atmCollection = 'atms';

  /// Call this once during app startup (e.g. from the Splash Screen).
  ///
  /// If ATMs already exist in Firestore, returns immediately.
  /// Otherwise, fetches from Google Places API first, then falls back
  /// to the local JSON seed data.
  Future<void> seedIfNeeded() async {
    try {
      // Quick-check: fetch a single document to see if data exists.
      final snapshot = await _db.collection(_atmCollection).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        debugPrint('[SeedService] ATMs already exist — skipping seed.');
        return;
      }

      // ── Step 1: Try Google Places API ────────────────────────────────
      debugPrint('[SeedService] No ATMs found. Fetching from Google Places API...');
      final placesService = PlacesService();
      final placesAtms = await placesService.fetchAtmsInServiceZone();

      if (placesAtms.isNotEmpty) {
        await _batchWrite(placesAtms);
        debugPrint('[SeedService] Seeded ${placesAtms.length} ATMs from Google Places API.');
        return;
      }

      // ── Step 2: Fall back to local JSON ──────────────────────────────
      debugPrint('[SeedService] Places API returned 0 results. Falling back to JSON seed.');
      final jsonAtms = await _loadJsonSeedData();
      await _batchWrite(jsonAtms);
      debugPrint('[SeedService] Seeded ${jsonAtms.length} ATMs from local JSON.');
    } catch (e) {
      // Non-fatal — the app can work without seed data.
      debugPrint('[SeedService] Seed failed (non-fatal): $e');
    }
  }

  /// Reads `assets/atm_seed_data.json` and parses it into a list of maps.
  Future<List<Map<String, dynamic>>> _loadJsonSeedData() async {
    final jsonString = await rootBundle.loadString('assets/atm_seed_data.json');
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Writes all ATMs to Firestore in a single batch for efficiency.
  /// Each ATM defaults to "unknown" status since we have no crowdsourced
  /// data yet — they'll appear as grey markers on the map.
  Future<void> _batchWrite(List<Map<String, dynamic>> atms) async {
    final batch = _db.batch();

    for (final atm in atms) {
      final docRef = _db.collection(_atmCollection).doc();

      // Build the initial votes map — all zeroes, status unknown.
      final votes = <String, int>{
        kStatusAvailable: 0,
        kStatusEmpty: 0,
        kStatusCrowded: 0,
        kStatusBroken: 0,
      };

      batch.set(docRef, {
        'name': atm['name'] ?? 'ATM',
        'bank': atm['bank'] ?? '',
        'placeId': atm['placeId'] ?? '',
        'address': atm['address'] ?? '',
        'lat': (atm['lat'] as num?)?.toDouble() ?? 0.0,
        'lng': (atm['lng'] as num?)?.toDouble() ?? 0.0,
        'votes': votes,
        // Default to UNKNOWN — every ATM starts grey until users report.
        'dominantStatus': kStatusUnknown,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}
