// =============================================================================
// map_screen.dart — Main Map Screen (Features 2, 3, 5 integration)
// =============================================================================
//
// Displays the Google Map with:
//   • Pre-populated ATM markers loaded from Firestore (Feature 2).
//   • Custom branded markers with dynamic colour coding (Feature 3).
//   • Semi-transparent red polygon overlays for uncovered areas (Feature 5).
//   • A status legend overlay at the bottom-right.
//
// Tapping a marker opens the StatusBottomSheet for reporting.
// Tapping inside a red zone shows a SnackBar "Service not yet available".
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../atm_model.dart';
import '../app_provider.dart';
import '../firestore_service.dart';
import '../status_bottom_sheet.dart';
import '../config/red_zone_config.dart';
import '../utils/marker_generator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ── Constants ────────────────────────────────────────────────────────────
  // Helwan, Cairo, Egypt — centre of the service area.
  static const LatLng _helwanCenter = LatLng(29.8502, 31.3342);
  static const double _initialZoom = 15.0;

  // ── Services ─────────────────────────────────────────────────────────────
  final FirestoreService _firestoreService = FirestoreService();
  final Completer<GoogleMapController> _mapController = Completer();

  // ── State ────────────────────────────────────────────────────────────────
  Set<Marker> _markers = {};
  Set<Polygon> _polygons = {};
  List<AtmModel> _atms = [];
  StreamSubscription<List<AtmModel>>? _atmSubscription;
  bool _markersReady = false;

  @override
  void initState() {
    super.initState();
    _subscribeToAtms();
    _buildRedZonePolygons();

    // Initialise custom markers after first frame (needs MediaQuery).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      await MarkerGenerator.instance.init(dpr);
      setState(() => _markersReady = true);

      // Rebuild markers now that custom icons are ready.
      if (_atms.isNotEmpty) {
        setState(() => _markers = _buildMarkers(_atms));
      }

      // Kick off a location fetch in the background.
      if (mounted) {
        context.read<AppProvider>().fetchUserLocation();
      }
    });
  }

  @override
  void dispose() {
    _atmSubscription?.cancel();
    super.dispose();
  }

  // ── Firestore ATM stream ─────────────────────────────────────────────────

  void _subscribeToAtms() {
    _atmSubscription = _firestoreService.getAtmsStream().listen((atms) {
      if (!mounted) return;
      setState(() {
        _atms = atms;
        _markers = _buildMarkers(atms);
      });
    });
  }

  // ── Feature 3: Custom branded markers ────────────────────────────────────

  Set<Marker> _buildMarkers(List<AtmModel> atms) {
    return atms.map((atm) {
      // effectiveStatus applies the 2-hour decay rule.
      final status = atm.effectiveStatus;
      return Marker(
        markerId: MarkerId(atm.id),
        position: LatLng(atm.latitude, atm.longitude),
        // Use custom branded marker if ready, otherwise fallback to default.
        icon: _markersReady
            ? MarkerGenerator.instance.getMarkerForStatus(status)
            : _fallbackMarkerIcon(status),
        infoWindow: InfoWindow(
          title: atm.name,
          snippet: atm.snippetWithTime,
        ),
        onTap: () => _onMarkerTapped(atm),
      );
    }).toSet();
  }

  /// Fallback to standard Google Maps hue-based markers while custom
  /// markers are still generating.
  BitmapDescriptor _fallbackMarkerIcon(AtmStatus status) {
    switch (status) {
      case AtmStatus.working:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case AtmStatus.empty:
      case AtmStatus.broken:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case AtmStatus.crowded:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case AtmStatus.unknown:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
  }

  // ── Feature 5: Red Zone Polygons ─────────────────────────────────────────

  /// Builds the semi-transparent red polygon overlays for areas outside
  /// the Helwan service boundary.
  void _buildRedZonePolygons() {
    final polygons = <Polygon>{};

    for (int i = 0; i < RedZoneConfig.allRedZones.length; i++) {
      polygons.add(
        Polygon(
          polygonId: PolygonId('red_zone_$i'),
          points: RedZoneConfig.allRedZones[i],
          fillColor: Colors.red.withOpacity(0.20),
          strokeColor: Colors.red.withOpacity(0.40),
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: _onRedZoneTapped,
        ),
      );
    }

    // Also draw the service area boundary as a subtle green border.
    polygons.add(
      Polygon(
        polygonId: const PolygonId('service_area'),
        points: RedZoneConfig.serviceAreaPolygon,
        fillColor: Colors.green.withOpacity(0.05),
        strokeColor: Colors.green.withOpacity(0.50),
        strokeWidth: 2,
      ),
    );

    setState(() => _polygons = polygons);
  }

  /// Called when the user taps inside a red zone polygon.
  void _onRedZoneTapped() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '🚫 الخدمة غير متاحة في هذه المنطقة بعد.\n'
          'Service not yet available in this area.',
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ── Map tap handler (check red zone on general tap too) ──────────────────

  void _onMapTapped(LatLng position) {
    if (RedZoneConfig.isInRedZone(position)) {
      _onRedZoneTapped();
    }
  }

  // ── Marker tap → open status bottom sheet ────────────────────────────────

  void _onMarkerTapped(AtmModel atm) {
    final provider = context.read<AppProvider>();
    final distance = provider.distanceToAtm(atm);

    // If we have a position and user is beyond 500m, block the report.
    if (distance != null && distance > AppProvider.kGeofenceRadiusMeters) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أنت بعيد عن هذا الـ ATM (${distance.toStringAsFixed(0)}م)، '
            'اقترب منه لتحديث حالته',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatusBottomSheet(atm: atm),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ATM Tracker – Helwan'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'My Location',
            onPressed: () async {
              await context.read<AppProvider>().fetchUserLocation();
              if (!mounted) return;
              final pos = context.read<AppProvider>().userPosition;
              if (pos != null) {
                final ctrl = await _mapController.future;
                ctrl.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(pos.latitude, pos.longitude),
                    _initialZoom,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _helwanCenter,
              zoom: _initialZoom,
            ),
            markers: _markers,
            // Feature 5: Red zone polygons + service area border.
            polygons: _polygons,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (ctrl) => _mapController.complete(ctrl),
            onTap: _onMapTapped,
          ),
          _buildLegend(),
          if (_atms.isEmpty)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Loading ATMs…'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        tooltip: 'إضافة ATM جديد',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('إضافة ATM جديد غير متاحة حالياً.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ── Status Legend ────────────────────────────────────────────────────────

  Widget _buildLegend() {
    const items = [
      (Colors.green, 'متاح (Working)'),
      (Colors.red, 'فاضي / عطلان (Empty)'),
      (Color(0xFFFF9800), 'مزدحم (Crowded)'),
      (Colors.grey, 'غير معروف (Unknown)'),
    ];

    return Positioned(
      bottom: 24,
      right: 12,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: item.$1,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(item.$2, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
