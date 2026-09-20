import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/background_recording_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundRecordingService.initialize();
  runApp(const SpokenLogApp());
}

class SpokenLogApp extends StatelessWidget {
  const SpokenLogApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE96B32),
      brightness: brightness,
    );
    final scheme = brightness == Brightness.light
        ? base.copyWith(
            primary: const Color(0xFFE96B32),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFFFEEE5),
            onPrimaryContainer: const Color(0xFF6A2B12),
            surface: Colors.white,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF8F8F6),
            surfaceContainer: const Color(0xFFF3F3F0),
            surfaceContainerHigh: const Color(0xFFEDEDEA),
            surfaceContainerHighest: const Color(0xFFE7E7E3),
            outline: const Color(0xFFB8B8B2),
            outlineVariant: const Color(0xFFE2E2DE),
          )
        : base;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.light ? const Color(0xFFF8F8F6) : scheme.surface,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpokenLog',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
