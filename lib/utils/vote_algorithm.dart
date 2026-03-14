// =============================================================================
// vote_algorithm.dart — Feature 4: Majority Vote Algorithm
// =============================================================================
//
// Implements the core crowdsourced status algorithm:
//
//   1. Collect all user reports submitted for an ATM.
//   2. Filter out any reports older than a configurable time window
//      (default: 2 hours) so the status reflects real-time reality.
//   3. Count the remaining votes per status category.
//   4. The status with the MOST votes wins (majority rules).
//   5. Ties or zero-vote situations fall back to "unknown".
//
// ─────────────────────────────────────────────────────────────────────────────
//
// DATA MODEL (each report / vote):
//
//   {
//     "userId":    "abc123",          // anonymous device UUID
//     "status":    "available",       // one of: available, empty, crowded, broken
//     "timestamp": <Firestore TS>,    // when the user submitted the report
//   }
//
// The [MajorityVoteAlgorithm] class is stateless and pure — it takes data in
// and returns results.  It does NOT read from Firestore directly; the caller
// passes in the raw reports list.
//
// TO INTEGRATE WITH YOUR BACKEND:
// Fetch reports from your API or Firestore subcollection and pass them to
// [computeStatus].  The function accepts a simple List<Map<String, dynamic>>.
// =============================================================================

import '../atm_model.dart';

/// A single crowdsourced report submitted by a user.
class AtmReport {
  /// The anonymous user ID (from Firebase anonymous auth / device UUID).
  final String userId;

  /// The status the user reported (e.g. 'available', 'empty', 'crowded', 'broken').
  final String status;

  /// When the report was submitted.
  final DateTime timestamp;

  const AtmReport({
    required this.userId,
    required this.status,
    required this.timestamp,
  });

  /// Factory constructor for building an [AtmReport] from a Firestore
  /// document map.
  ///
  /// Expects keys: 'userId', 'status' (or 'statusKey'), 'timestamp' (or 'votedAt').
  factory AtmReport.fromMap(Map<String, dynamic> map) {
    final rawTs = map['timestamp'] ?? map['votedAt'];
    DateTime ts;
    if (rawTs is DateTime) {
      ts = rawTs;
    } else if (rawTs != null && rawTs.runtimeType.toString().contains('Timestamp')) {
      // Firestore Timestamp — call .toDate() dynamically to avoid hard
      // dependency on cloud_firestore in this utility file.
      ts = (rawTs as dynamic).toDate() as DateTime;
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return AtmReport(
      userId: (map['userId'] as String?) ?? 'unknown',
      status: (map['status'] as String?) ?? (map['statusKey'] as String?) ?? kStatusUnknown,
      timestamp: ts,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAJORITY VOTE ALGORITHM
// ─────────────────────────────────────────────────────────────────────────────

class MajorityVoteAlgorithm {
  /// The time window within which reports are considered "recent".
  /// Reports older than this are excluded from the calculation.
  ///
  /// Default: 2 hours (as per specification).
  /// Adjust this value to make the status more or less reactive.
  final Duration timeWindow;

  const MajorityVoteAlgorithm({
    this.timeWindow = const Duration(hours: 2),
  });

  // ── Step 1: Filter stale reports ────────────────────────────────────────

  /// Returns only the reports that were submitted within [timeWindow] of [now].
  ///
  /// Example:
  ///   If timeWindow = 2 hours and now = 14:00,
  ///   only reports from 12:00 onwards are kept.
  List<AtmReport> filterRecentReports(
    List<AtmReport> reports, {
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(timeWindow);
    return reports.where((r) => r.timestamp.isAfter(cutoff)).toList();
  }

  // ── Step 2: Count votes per status ──────────────────────────────────────

  /// Tallies how many reports exist for each status key.
  ///
  /// Returns a map like: { 'available': 6, 'empty': 4, 'crowded': 0, 'broken': 0 }
  Map<String, int> countVotes(List<AtmReport> reports) {
    final counts = <String, int>{
      kStatusAvailable: 0,
      kStatusEmpty: 0,
      kStatusCrowded: 0,
      kStatusBroken: 0,
    };

    for (final report in reports) {
      // Normalise the key (handle 'working' → 'available', etc.)
      final normalised = _normaliseStatusKey(report.status);
      counts[normalised] = (counts[normalised] ?? 0) + 1;
    }

    return counts;
  }

  // ── Step 3: Determine dominant status ───────────────────────────────────

  /// The main entry point.  Given a list of ALL reports for an ATM, this:
  ///   1. Filters out reports older than [timeWindow].
  ///   2. Counts votes per status.
  ///   3. Returns the status with the most votes (majority rules).
  ///
  /// Returns [kStatusUnknown] if:
  ///   - There are no recent reports.
  ///   - There is a tie between two or more statuses.
  ///
  /// Example:
  ///   10 reports in the last 2 hours:
  ///     6 × "empty", 4 × "available"
  ///   → returns "empty" (Red marker).
  String computeStatus(List<AtmReport> allReports, {DateTime? now}) {
    // Step 1: filter.
    final recent = filterRecentReports(allReports, now: now);

    if (recent.isEmpty) return kStatusUnknown;

    // Step 2: count.
    final votes = countVotes(recent);

    // Step 3: find the majority.
    return _findMajority(votes);
  }

  /// Convenience method that returns an [AtmStatus] enum instead of a
  /// raw string key.
  AtmStatus computeAtmStatus(List<AtmReport> allReports, {DateTime? now}) {
    return AtmStatus.fromKey(computeStatus(allReports, now: now));
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  /// Finds the status key with the highest vote count.
  /// Returns [kStatusUnknown] on tie or zero votes.
  String _findMajority(Map<String, int> votes) {
    String best = kStatusUnknown;
    int bestCount = 0;
    bool tie = false;

    for (final entry in votes.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        best = entry.key;
        tie = false;
      } else if (entry.value == bestCount && entry.value > 0) {
        tie = true;
      }
    }

    // If all counts are 0 or there's a tie, we can't determine a clear winner.
    if (bestCount == 0 || tie) return kStatusUnknown;
    return best;
  }

  /// Normalises alternative status keys (e.g. 'working' → 'available').
  String _normaliseStatusKey(String key) {
    switch (key) {
      case 'working':
      case kStatusAvailable:
        return kStatusAvailable;
      case kStatusEmpty:
      case 'empty':
        return kStatusEmpty;
      case kStatusCrowded:
      case 'crowded':
        return kStatusCrowded;
      case kStatusBroken:
      case 'broken':
        return kStatusBroken;
      default:
        return kStatusUnknown;
    }
  }
}
