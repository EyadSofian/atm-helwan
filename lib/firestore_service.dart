import 'package:cloud_firestore/cloud_firestore.dart';
import 'atm_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _atmCollection = 'atms';
  static const String _voteCollection = 'userVotes';

  /// Returns a live stream of all ATMs from Firestore.
  Stream<List<AtmModel>> getAtmsStream() {
    return _db.collection(_atmCollection).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return AtmModel.fromMap(doc.id, doc.data());
      }).toList();
    });
  }

  /// Checks whether [uid] has already voted on [atmId] within the last 24 h.
  Future<bool> hasVotedRecently({
    required String uid,
    required String atmId,
  }) async {
    final docId = '${uid}_$atmId';
    final doc = await _db.collection(_voteCollection).doc(docId).get();
    if (!doc.exists) return false;

    final data = doc.data();
    final rawTs = data?['votedAt'];
    if (rawTs is Timestamp) {
      final votedAt = rawTs.toDate();
      return DateTime.now().difference(votedAt).inHours < 24;
    }
    return false;
  }

  /// Casts a vote for [statusKey] on the ATM with [atmId].
  ///
  /// Uses a Firestore transaction to safely increment the vote count
  /// and recompute [dominantStatus]. Also records the voter in
  /// `userVotes/{uid}_{atmId}`.
  Future<void> castVote({
    required String atmId,
    required String statusKey,
    required String uid,
  }) async {
    final atmRef = _db.collection(_atmCollection).doc(atmId);
    final voteDocId = '${uid}_$atmId';

    await _db.runTransaction((tx) async {
      final snap = await tx.get(atmRef);
      if (!snap.exists) return;

      final data = snap.data()!;
      final rawVotes = data['votes'];

      // Build current votes map.
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

      // Increment the chosen status.
      votes[statusKey] = (votes[statusKey] ?? 0) + 1;

      // Recompute dominant status.
      final dominant = computeDominantStatus(votes);

      tx.update(atmRef, {
        'votes': votes,
        'dominantStatus': dominant,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Record the vote.
      tx.set(_db.collection(_voteCollection).doc(voteDocId), {
        'uid': uid,
        'atmId': atmId,
        'statusKey': statusKey,
        'votedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Convenience wrapper used by AppProvider.submitReport.
  /// Increments the vote for [statusKey] and recomputes dominant status.
  Future<void> updateAtmStatus({
    required String atmId,
    required AtmStatus newStatus,
  }) async {
    final statusKey = newStatus.key;
    final atmRef = _db.collection(_atmCollection).doc(atmId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(atmRef);
      if (!snap.exists) return;

      final data = snap.data()!;
      final rawVotes = data['votes'];

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

      votes[statusKey] = (votes[statusKey] ?? 0) + 1;
      final dominant = computeDominantStatus(votes);

      tx.update(atmRef, {
        'votes': votes,
        'dominantStatus': dominant,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Adds a brand-new ATM document to Firestore.
  Future<void> addAtm({
    required String name,
    required String bank,
    required String statusValue,
    required double lat,
    required double lng,
    required String addedBy,
  }) async {
    final votes = <String, int>{
      kStatusAvailable: statusValue == kStatusAvailable ? 1 : 0,
      kStatusEmpty: statusValue == kStatusEmpty ? 1 : 0,
      kStatusCrowded: statusValue == kStatusCrowded ? 1 : 0,
      kStatusBroken: statusValue == kStatusBroken ? 1 : 0,
    };

    await _db.collection(_atmCollection).add({
      'name': name,
      'bank': bank,
      'lat': lat,
      'lng': lng,
      'votes': votes,
      'dominantStatus': computeDominantStatus(votes),
      'lastUpdated': FieldValue.serverTimestamp(),
      'addedBy': addedBy,
    });
  }
}
