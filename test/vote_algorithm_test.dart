// =============================================================================
// vote_algorithm_test.dart — Unit tests for the Majority Vote Algorithm
// =============================================================================
//
// Tests the core crowdsourced voting logic:
//   • Filtering out stale reports (> 2 hours old).
//   • Counting votes per status.
//   • Determining the majority winner.
//   • Handling ties and zero-vote edge cases.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:atm_helwan/utils/vote_algorithm.dart';
import 'package:atm_helwan/atm_model.dart';

void main() {
  const algorithm = MajorityVoteAlgorithm(
    timeWindow: Duration(hours: 2),
  );

  final now = DateTime(2026, 3, 14, 14, 0, 0); // 14:00

  // ── Helper to create reports quickly ─────────────────────────────────────

  AtmReport _report(String status, DateTime timestamp) {
    return AtmReport(userId: 'user1', status: status, timestamp: timestamp);
  }

  // ── Tests ────────────────────────────────────────────────────────────────

  group('filterRecentReports', () {
    test('keeps reports within the 2-hour window', () {
      final reports = [
        _report('available', now.subtract(const Duration(minutes: 30))),
        _report('empty', now.subtract(const Duration(hours: 1))),
        _report('available', now.subtract(const Duration(hours: 1, minutes: 59))),
      ];

      final recent = algorithm.filterRecentReports(reports, now: now);
      expect(recent.length, 3);
    });

    test('removes reports older than 2 hours', () {
      final reports = [
        _report('available', now.subtract(const Duration(minutes: 30))),
        _report('empty', now.subtract(const Duration(hours: 3))), // too old
        _report('broken', now.subtract(const Duration(hours: 5))), // too old
      ];

      final recent = algorithm.filterRecentReports(reports, now: now);
      expect(recent.length, 1);
      expect(recent.first.status, 'available');
    });

    test('returns empty list when all reports are stale', () {
      final reports = [
        _report('available', now.subtract(const Duration(hours: 4))),
        _report('empty', now.subtract(const Duration(hours: 10))),
      ];

      final recent = algorithm.filterRecentReports(reports, now: now);
      expect(recent, isEmpty);
    });
  });

  group('countVotes', () {
    test('correctly tallies votes per status', () {
      final reports = [
        _report('available', now),
        _report('available', now),
        _report('empty', now),
        _report('crowded', now),
        _report('available', now),
      ];

      final counts = algorithm.countVotes(reports);
      expect(counts[kStatusAvailable], 3);
      expect(counts[kStatusEmpty], 1);
      expect(counts[kStatusCrowded], 1);
      expect(counts[kStatusBroken], 0);
    });

    test('normalises "working" to "available"', () {
      final reports = [
        _report('working', now),
        _report('working', now),
      ];

      final counts = algorithm.countVotes(reports);
      expect(counts[kStatusAvailable], 2);
    });
  });

  group('computeStatus (full pipeline)', () {
    test('returns majority status when one clearly wins', () {
      // 6 "empty" vs 4 "available" → should return "empty" (Red)
      final reports = [
        for (int i = 0; i < 6; i++)
          _report('empty', now.subtract(Duration(minutes: 10 + i))),
        for (int i = 0; i < 4; i++)
          _report('available', now.subtract(Duration(minutes: 10 + i))),
      ];

      final result = algorithm.computeStatus(reports, now: now);
      expect(result, kStatusEmpty);
    });

    test('returns "unknown" on tie', () {
      final reports = [
        _report('available', now.subtract(const Duration(minutes: 10))),
        _report('empty', now.subtract(const Duration(minutes: 20))),
      ];

      final result = algorithm.computeStatus(reports, now: now);
      expect(result, kStatusUnknown);
    });

    test('returns "unknown" when all reports are stale', () {
      final reports = [
        _report('available', now.subtract(const Duration(hours: 5))),
      ];

      final result = algorithm.computeStatus(reports, now: now);
      expect(result, kStatusUnknown);
    });

    test('returns "unknown" when report list is empty', () {
      final result = algorithm.computeStatus([], now: now);
      expect(result, kStatusUnknown);
    });

    test('ignores old reports and uses only recent majority', () {
      final reports = [
        // Recent (within 2 hours): 2 "crowded"
        _report('crowded', now.subtract(const Duration(minutes: 15))),
        _report('crowded', now.subtract(const Duration(minutes: 30))),
        // Old (should be filtered out): 5 "available"
        _report('available', now.subtract(const Duration(hours: 3))),
        _report('available', now.subtract(const Duration(hours: 4))),
        _report('available', now.subtract(const Duration(hours: 5))),
        _report('available', now.subtract(const Duration(hours: 6))),
        _report('available', now.subtract(const Duration(hours: 7))),
      ];

      final result = algorithm.computeStatus(reports, now: now);
      expect(result, kStatusCrowded);
    });
  });

  group('computeAtmStatus (enum version)', () {
    test('returns AtmStatus.empty for majority empty', () {
      final reports = [
        _report('empty', now.subtract(const Duration(minutes: 5))),
        _report('empty', now.subtract(const Duration(minutes: 10))),
        _report('available', now.subtract(const Duration(minutes: 15))),
      ];

      final result = algorithm.computeAtmStatus(reports, now: now);
      expect(result, AtmStatus.empty);
    });
  });
}
