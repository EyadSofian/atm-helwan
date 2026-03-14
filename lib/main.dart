// =============================================================================
// main.dart — Application Entry Point
// =============================================================================
//
// Sets up the Provider tree and launches the SplashScreen.
//
// Firebase initialisation and anonymous sign-in are now handled INSIDE the
// SplashScreen (see lib/screens/splash_screen.dart) so the splash UI is
// visible while the heavy init work happens in the background.
//
// Authentication:
//   The app uses Firebase Anonymous Auth — NO login / registration required.
//   Each device gets a stable anonymous UID which is used to track votes
//   and enforce cooldowns.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_provider.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Note: Firebase.initializeApp() is called from SplashScreen so the
  // splash UI appears instantly while Firebase boots in the background.

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>(
          create: (_) => AppProvider(),
        ),
      ],
      child: const AtmHelwanApp(),
    ),
  );
}

class AtmHelwanApp extends StatelessWidget {
  const AtmHelwanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ATM Tracker – Helwan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      // Start with the Splash Screen → auto-navigates to MapScreen.
      home: const SplashScreen(),
    );
  }
}
