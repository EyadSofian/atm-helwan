import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'atm_model.dart';
import 'firestore_service.dart';
import 'location_service.dart';

enum SubmitResult {
  success,
  tooFar,
  cooldownActive,
  locationError,
  firestoreError,
}

class AppProvider extends ChangeNotifier {
  final LocationService _locationService;
  final FirestoreService _firestoreService;

  AppProvider({
    LocationService? locationService,
    FirestoreService? firestoreService,
  })  : _locationService = locationService ?? LocationService(),
        _firestoreService = firestoreService ?? FirestoreService();

  // ── State ────────────────────────────────────────────────────────────────

  Position? _userPosition;
  bool _isFetchingLocation = false;
  String? _locationError;

  bool _isSubmitting = false;
  String? _submitError;

  static const int _cooldownMinutes = 15;
  static const double kGeofenceRadiusMeters = 500.0;
  static const String _prefKey = 'last_report_timestamp';

  Position? get userPosition => _userPosition;
  bool get isFetchingLocation => _isFetchingLocation;
  String? get locationError => _locationError;
  bool get isSubmitting => _isSubmitting;
  String? get submitError => _submitError;

  // ── Location ─────────────────────────────────────────────────────────────

  Future<void> fetchUserLocation() async {
    _isFetchingLocation = true;
    _locationError = null;
    notifyListeners();

    try {
      _userPosition = await _locationService.getCurrentPosition();
    } catch (e) {
      _locationError = e.toString();
    } finally {
      _isFetchingLocation = false;
      notifyListeners();
    }
  }

  /// Returns the distance in meters between the user and an ATM.
  /// Returns `null` if user position is unknown.
  double? distanceToAtm(AtmModel atm) {
    if (_userPosition == null) return null;
    return _locationService.distanceBetween(
      startLatitude: _userPosition!.latitude,
      startLongitude: _userPosition!.longitude,
      endLatitude: atm.latitude,
      endLongitude: atm.longitude,
    );
  }

  // ── Cooldown ─────────────────────────────────────────────────────────────

  /// Returns null when the cooldown is not active.
  /// Returns a human-readable remaining time string when active.
  Future<String?> _checkCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_prefKey);
    if (lastMs == null) return null;

    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    final elapsed = DateTime.now().difference(last);

    if (elapsed.inMinutes < _cooldownMinutes) {
      final remaining = _cooldownMinutes - elapsed.inMinutes;
      final remainingSeconds = 60 - elapsed.inSeconds % 60;
      return '${remaining}m ${remainingSeconds}s';
    }
    return null;
  }

  Future<void> _stampCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);
  }

  // ── Report Submission ─────────────────────────────────────────────────────

  /// Validates geofencing + cooldown, then writes to Firestore.
  /// Returns a [SubmitResult] and an optional human-readable message.
  Future<(SubmitResult, String?)> submitReport({
    required AtmModel atm,
    required AtmStatus newStatus,
  }) async {
    _isSubmitting = true;
    _submitError = null;
    notifyListeners();

    try {
      // 1. Ensure we have the user's location.
      if (_userPosition == null) {
        await fetchUserLocation();
        if (_userPosition == null) {
          return (
            SubmitResult.locationError,
            _locationError ?? 'Could not determine your location.',
          );
        }
      }

      // 2. Geofencing check.
      final distance = distanceToAtm(atm) ?? double.infinity;

      if (distance > kGeofenceRadiusMeters) {
        final distStr = distance.toStringAsFixed(0);
        return (
          SubmitResult.tooFar,
          'أنت على بعد ${distStr}م. لازم تكون أقرب من ${kGeofenceRadiusMeters.toInt()}م.',
        );
      }

      // 3. Cooldown check.
      final cooldownMsg = await _checkCooldown();
      if (cooldownMsg != null) {
        return (
          SubmitResult.cooldownActive,
          'Please wait $cooldownMsg before submitting another report.',
        );
      }

      // 4. Write to Firestore.
      await _firestoreService.updateAtmStatus(
        atmId: atm.id,
        newStatus: newStatus,
      );

      // 5. Stamp the cooldown timer.
      await _stampCooldown();

      return (SubmitResult.success, null);
    } catch (e) {
      return (SubmitResult.firestoreError, 'Submission failed: $e');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // ── Add New ATM ──────────────────────────────────────────────────────────

  /// Adds a brand-new ATM to Firestore using the user's current location.
  /// Returns `(true, null)` on success or `(false, errorMessage)` on failure.
  Future<(bool, String?)> addNewAtm({
    required String name,
    required String bank,
    required AtmStatus status,
  }) async {
    _isSubmitting = true;
    _submitError = null;
    notifyListeners();

    try {
      // 1. Ensure we have the user's location.
      if (_userPosition == null) {
        await fetchUserLocation();
        if (_userPosition == null) {
          return (false, _locationError ?? 'Could not determine your location.');
        }
      }

      // 2. Get anonymous user ID.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

      // 3. Write to Firestore.
      await _firestoreService.addAtm(
        name: name,
        bank: bank,
        statusValue: status.name,
        lat: _userPosition!.latitude,
        lng: _userPosition!.longitude,
        addedBy: uid,
      );

      return (true, null);
    } catch (e) {
      return (false, 'Failed to add ATM: $e');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
