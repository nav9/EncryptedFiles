import 'package:flutter/material.dart';

class AppThemes {
  AppThemes._();

  static const Color deepBlue = Color(0xFF0D47A1);
  static const Color accentBlue = Color(0xFF1976D2);
  static const Color darkSurface = Color(0xFF0A1628);
  static const Color darkBackground = Color(0xFF050B14);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: deepBlue,
        brightness: Brightness.dark,
        primary: accentBlue,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkBackground,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 48,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: darkSurface),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentBlue,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: deepBlue,
        brightness: Brightness.light,
        primary: deepBlue,
      ),
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 48,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
