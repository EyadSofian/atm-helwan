// =============================================================================
// seed_service.dart — Feature 2: Pre-Populated ATMs (Seed from JSON)
// =============================================================================
//
// Responsible for loading the local JSON asset that contains pre-defined ATM
// locations and writing them to Firestore **only if the collection is empty**
// (i.e. first run).
//
// The JSON file is located at: assets/atm_seed_data.json
//
// HOW TO ADD YOUR OWN ATMs:
// Simply add entries to that JSON file with the fields:
//   { "name": "...", "bank": "...", "lat": 29.xxxx, "lng": 31.xxxx }
//
// HOW TO REPLACE WITH A BACKEND API:
// Replace the body of [_loadSeedData] with an HTTP call to your endpoint
// and parse the response into the same List<Map<String, dynamic>> format.
// =============================================================================

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../atm_model.dart';

class SeedService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _atmCollection = 'atms';

  /// Call this once during app startup (e.g. from the Splash Screen).
  /// It checks whether the "atms" Firestore collection already contains
  /// documents.  If it does, the function returns immediately — no duplicate
  /// data will be written.
  ///
  /// If the collection is empty (first launch), it reads the local JSON
  /// asset and batch-writes all ATMs into Firestore.
  Future<void> seedIfNeeded() async {
    try {
      // Quick-check: fetch a single document to see if data exists.
      final snapshot = await _db
          .collection(_atmCollection)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        debugPrint('[SeedService] ATMs already exist — skipping seed.');
        return;
      }

      // No documents found → load and write seed data.
      final seedAtms = await _loadSeedData();
      await _batchWrite(seedAtms);
      debugPrint('[SeedService] Seeded ${seedAtms.length} ATMs successfully.');
    } catch (e) {
      // Non-fatal.  The app can work without seed data if ATMs are added
      // manually through the "Add ATM" flow later.
      debugPrint('[SeedService] Seed failed (non-fatal): $e');
    }
  }

  /// Reads `assets/atm_seed_data.json` and parses it into a list of maps.
  ///
  /// ──────────────────────────────────────────────────────────────────────
  /// TO INTEGRATE WITH A BACKEND API:
  /// Replace the body of this method with an HTTP request, e.g.:
  ///
  ///   final response = await http.get(Uri.parse('https://your-api.com/atms'));
  ///   return List<Map<String, dynamic>>.from(jsonDecode(response.body));
  ///
  /// The rest of the seed pipeline will work without changes.
  /// ──────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _loadSeedData() async {
    final jsonString = await rootBundle.loadString('assets/atm_seed_data.json');
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Writes all seed ATMs to Firestore in a single batch for efficiency.
  Future<void> _batchWrite(List<Map<String, dynamic>> atms) async {
    final batch = _db.batch();

    for (final atm in atms) {
      final docRef = _db.collection(_atmCollection).doc(); // auto-ID

      // Build the initial votes map — all zeroes, status unknown.
      final votes = <String, int>{
        kStatusAvailable: 0,
        kStatusEmpty: 0,
        kStatusCrowded: 0,
        kStatusBroken: 0,
      };

      batch.set(docRef, {
        'name': atm['name'] ?? 'Unnamed ATM',
        'bank': atm['bank'] ?? '',
        'lat': (atm['lat'] as num?)?.toDouble() ?? 0.0,
        'lng': (atm['lng'] as num?)?.toDouble() ?? 0.0,
        'votes': votes,
        'dominantStatus': kStatusUnknown,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}
