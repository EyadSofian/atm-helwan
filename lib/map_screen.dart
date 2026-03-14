import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'atm_model.dart';
import 'app_provider.dart';
import 'firestore_service.dart';
import 'status_bottom_sheet.dart';
import 'add_atm_bottom_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Helwan, Cairo, Egypt
  static const LatLng _helwanCenter = LatLng(29.8502, 31.3342);
  static const double _initialZoom = 15.0;

  final FirestoreService _firestoreService = FirestoreService();
  final Completer<GoogleMapController> _mapController = Completer();

  Set<Marker> _markers = {};
  List<AtmModel> _atms = [];
  StreamSubscription<List<AtmModel>>? _atmSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToAtms();
    // Kick off a location fetch in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().fetchUserLocation();
    });
  }

  @override
  void dispose() {
    _atmSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToAtms() {
    _atmSubscription = _firestoreService.getAtmsStream().listen((atms) {
      if (!mounted) return;
      setState(() {
        _atms = atms;
        _markers = _buildMarkers(atms);
      });
    });
  }

  Set<Marker> _buildMarkers(List<AtmModel> atms) {
    return atms.map((atm) {
      // effectiveStatus already applies the 3-hour decay rule.
      final status = atm.effectiveStatus;
      return Marker(
        markerId: MarkerId(atm.id),
        position: LatLng(atm.latitude, atm.longitude),
        icon: _markerIconForStatus(status),
        infoWindow: InfoWindow(
          title: atm.name,
          snippet: atm.snippetWithTime,
        ),
        onTap: () => _onMarkerTapped(atm),
      );
    }).toSet();
  }

  BitmapDescriptor _markerIconForStatus(AtmStatus status) {
    switch (status) {
      case AtmStatus.working:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case AtmStatus.empty:
      case AtmStatus.broken:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case AtmStatus.crowded:
        return BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow);
      case AtmStatus.unknown:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

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
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (ctrl) => _mapController.complete(ctrl),
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
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const AddAtmBottomSheet(),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildLegend() {
    const items = [
      (Colors.green, 'متاح'),
      (Colors.red, 'فاضي / عطلان'),
      (Colors.yellow, 'مزدحم'),
      (Colors.blueAccent, 'غير معروف'),
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
