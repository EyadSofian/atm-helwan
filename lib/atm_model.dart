import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── AtmStatus enum ─────────────────────────────────────────────────────────

enum AtmStatus {
  working,
  empty,
  crowded,
  broken,
  unknown;

  /// Arabic label for UI display.
  String get label {
    switch (this) {
      case AtmStatus.working:
        return 'متاح';
      case AtmStatus.empty:
        return 'فاضي';
      case AtmStatus.crowded:
        return 'مزدحم';
      case AtmStatus.broken:
        return 'عطلان';
      case AtmStatus.unknown:
        return 'غير معروف';
    }
  }

  /// The Firestore string key for this status.
  String get key {
    switch (this) {
      case AtmStatus.working:
        return kStatusAvailable;
      case AtmStatus.empty:
        return kStatusEmpty;
      case AtmStatus.crowded:
        return kStatusCrowded;
      case AtmStatus.broken:
        return kStatusBroken;
      case AtmStatus.unknown:
        return kStatusUnknown;
    }
  }

  /// Parse a Firestore string key into an [AtmStatus].
  static AtmStatus fromKey(String key) {
    switch (key) {
      case kStatusAvailable:
      case 'working':
        return AtmStatus.working;
      case kStatusEmpty:
      case 'empty':
        return AtmStatus.empty;
      case kStatusCrowded:
      case 'crowded':
        return AtmStatus.crowded;
      case kStatusBroken:
      case 'broken':
        return AtmStatus.broken;
      default:
        return AtmStatus.unknown;
    }
  }
}

// ── Status constants ───────────────────────────────────────────────────────

const kStatusAvailable = 'available';
const kStatusEmpty = 'empty';
const kStatusCrowded = 'crowded';
const kStatusBroken = 'broken';
const kStatusUnknown = 'unknown';

const List<String> kAllStatuses = [
  kStatusAvailable,
  kStatusEmpty,
  kStatusCrowded,
  kStatusBroken,
];

/// Arabic label for each status key.
String statusLabel(String key) {
  switch (key) {
    case kStatusAvailable:
      return 'متاح';
    case kStatusEmpty:
      return 'فاضي';
    case kStatusCrowded:
      return 'مزدحم';
    case kStatusBroken:
      return 'عطلان';
    default:
      return 'غير معروف';
  }
}

/// Color for each status key (matching the spec).
Color statusColor(String key) {
  switch (key) {
    case kStatusAvailable:
      return const Color(0xFF4CAF50);
    case kStatusEmpty:
      return const Color(0xFFFF9800);
    case kStatusCrowded:
      return const Color(0xFFFFC107);
    case kStatusBroken:
      return const Color(0xFFF44336);
    default:
      return const Color(0xFF607D8B); // blue-grey for unknown
  }
}

/// Icon for each status key.
IconData statusIcon(String key) {
  switch (key) {
    case kStatusAvailable:
      return Icons.check_circle_outline;
    case kStatusEmpty:
      return Icons.money_off;
    case kStatusCrowded:
      return Icons.people;
    case kStatusBroken:
      return Icons.cancel_outlined;
    default:
      return Icons.help_outline;
  }
}

// ── Model ──────────────────────────────────────────────────────────────────

class AtmModel {
  final String id;
  final String placeId;
  final String name;
  final double lat;
  final double lng;
  final Map<String, int> votes;
  final String dominantStatus;
  final DateTime lastUpdated;

  const AtmModel({
    required this.id,
    this.placeId = '',
    required this.name,
    required this.lat,
    required this.lng,
    this.votes = const {
      kStatusAvailable: 0,
      kStatusEmpty: 0,
      kStatusCrowded: 0,
      kStatusBroken: 0,
    },
    this.dominantStatus = kStatusUnknown,
    required this.lastUpdated,
  });

  // ── Convenience getters used by map_screen / status_bottom_sheet ───────

  /// Alias so screens can use `atm.latitude` / `atm.longitude`.
  double get latitude => lat;
  double get longitude => lng;

  /// Applies a 2-hour time-decay rule (matching the majority vote window):
  /// if the last report is older than 2 hours → unknown.
  AtmStatus get effectiveStatus {
    final age = DateTime.now().difference(lastUpdated);
    if (age.inHours >= 2) return AtmStatus.unknown;
    return AtmStatus.fromKey(dominantStatus);
  }

  /// A short snippet showing the Arabic status and a relative time.
  String get snippetWithTime {
    final label = effectiveStatus.label;
    final diff = DateTime.now().difference(lastUpdated);
    String timeStr;
    if (diff.inMinutes < 1) {
      timeStr = 'دلوقتي';
    } else if (diff.inMinutes < 60) {
      timeStr = 'من ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      timeStr = 'من ${diff.inHours} ساعة';
    } else {
      timeStr = 'من ${diff.inDays} يوم';
    }
    return '$label – $timeStr';
  }

  /// Total number of votes across all statuses.
  int get totalVotes => votes.values.fold(0, (a, b) => a + b);

  /// Color corresponding to the dominant status.
  Color get markerColor => statusColor(dominantStatus);

  /// Arabic label for the dominant status.
  String get statusLabelText => statusLabel(dominantStatus);

  factory AtmModel.fromMap(String docId, Map<String, dynamic> map) {
    final rawTs = map['lastUpdated'];
    DateTime ts;
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }

    // Parse votes map safely.
    final rawVotes = map['votes'];
    Map<String, int> votes = {
      kStatusAvailable: 0,
      kStatusEmpty: 0,
      kStatusCrowded: 0,
      kStatusBroken: 0,
    };
    if (rawVotes is Map) {
      for (final key in kAllStatuses) {
        final v = rawVotes[key];
        if (v is num) votes[key] = v.toInt();
      }
    }

    return AtmModel(
      id: docId,
      placeId: (map['placeId'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Unnamed ATM',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      votes: votes,
      dominantStatus: (map['dominantStatus'] as String?) ?? kStatusUnknown,
      lastUpdated: ts,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'placeId': placeId,
      'name': name,
      'lat': lat,
      'lng': lng,
      'votes': votes,
      'dominantStatus': dominantStatus,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtmModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Given a votes map, computes the dominant status key.
/// Returns [kStatusUnknown] if all are 0 or there's a tie involving 0.
String computeDominantStatus(Map<String, int> votes) {
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

  if (bestCount == 0 || tie) return kStatusUnknown;
  return best;
}
