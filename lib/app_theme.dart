import 'package:flutter/material.dart';

class AppTheme {
  // Define all colors here. If you change them here, they will change across the entire app.
  static const Color primaryColor = Color(0xFF4F46E5); // Indigo
  static const Color secondaryColor = Color(0xFF7C3AED); // Violet
  
  static const List<Color> gradientColors = [
    primaryColor,
    secondaryColor,
  ];

  static const List<Color> gradientColors1 = [
    Color.fromARGB(255, 255, 0, 0),
    Color.fromARGB(255, 255, 0, 8),
  ];

  static const Color scaffoldBackgroundColor = Color(0xFFF8FAFC); // Slate-50
  static const Color cardBackgroundColor = Colors.white;
  static const Color appBarBackgroundColor = Colors.white;
  static const Color textColor = Color(0xFF0F172A); // Slate-900
  static const Color subtitleColor = Color(0xFF64748B); // Slate-500
  static const Color borderColor = Color(0xFFE2E8F0); // Slate-200
  
  // Status Badge Colors
  static const Color statusOnTheWayBg = Color(0xFFDBEAFE);
  static const Color statusOnTheWayText = Color(0xFF1D4ED8);
  static const Color statusDraftBg = Color(0xFFF1F5F9);
  static const Color statusDraftText = Color(0xFF475569);
  static const Color statusCompletedBg = Color(0xFFD1FAE5);
  static const Color statusCompletedText = Color(0xFF047857);
  static const Color statusPendingBg = Color(0xFFFEF3C7);
  static const Color statusPendingText = Color(0xFFB45309);
   static const Color red = Color.fromARGB(255, 255, 0, 0);


// splash screen colors
static const Color kBlue =  Color(0xFF2196F3);
static const Color kBlueLight =  Color(0xFF64B5F6);
static const Color kBlueDark =  Color(0xFF1976D2);


  // Return ThemeData for MaterialApp
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: appBarBackgroundColor,
        foregroundColor: textColor,
        elevation: 0,
        iconTheme: IconThemeData(
          color: textColor,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBackgroundColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
