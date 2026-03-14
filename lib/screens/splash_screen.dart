// =============================================================================
// splash_screen.dart — Feature 1: Lightweight Splash Screen
// =============================================================================
//
// Displays a solid indigo background with the app logo centered on screen.
// While visible, it initialises Firebase and fetches the user's location in
// the background.  After a **maximum of 2 seconds** (or when init finishes,
// whichever comes FIRST), it seamlessly transitions to the MapScreen.
//
// No user interaction is required.
// =============================================================================

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_provider.dart';
import '../firebase_options.dart';
import '../services/seed_service.dart';
import 'map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // ── Animation controller for a subtle fade-in of the logo ────────────────
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    // Logo fades in over 600 ms for a polished feel.
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    // Kick off background work + max-2-second timer in parallel.
    _initAndNavigate();
  }

  /// Runs Firebase init, anonymous sign-in, ATM seed, and location fetch
  /// concurrently with a 2-second timer.  Navigates to MapScreen as soon as
  /// BOTH the timer AND the init work are done.
  Future<void> _initAndNavigate() async {
    // --- Background initialisation (runs in parallel with the timer) --------
    final initFuture = _backgroundInit();
    final timerFuture = Future.delayed(const Duration(seconds: 2));

    // Wait for BOTH to complete (so the splash stays at least 2 s).
    await Future.wait([initFuture, timerFuture]);

    if (!mounted) return;

    // Navigate to the main Map Screen, replacing the splash in the stack.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MapScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  /// All heavy lifting that should happen behind the splash.
  Future<void> _backgroundInit() async {
    try {
      // 1. Initialise Firebase.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 2. Sign in anonymously (device UUID-style tracking, no login).
      await _signInAnonymously();

      // 3. Seed pre-populated ATMs if this is the first run.
      await SeedService().seedIfNeeded();

      // 4. Begin fetching the user's GPS location (non-blocking for nav).
      if (mounted) {
        context.read<AppProvider>().fetchUserLocation();
      }
    } catch (e) {
      // Non-fatal — the app can still run in read-only mode.
      debugPrint('[SplashScreen] Background init error: $e');
    }
  }

  /// Firebase anonymous auth — provides a stable UID for Firestore rules
  /// without requiring the user to create an account.
  Future<void> _signInAnonymously() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Solid brand-color background.
      backgroundColor: const Color(0xFF303F9F), // Indigo 700
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── App Logo / Icon ──────────────────────────────────────────
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.atm_rounded,
                    size: 64,
                    color: Color(0xFF303F9F),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── App Name ─────────────────────────────────────────────────
              const Text(
                'ATM Helwan',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              // ── Tagline ──────────────────────────────────────────────────
              Text(
                'اعرف حالة الـ ATM قبل ما تروح',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),

              const SizedBox(height: 40),

              // ── Loading indicator ────────────────────────────────────────
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
