import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF202C4D); // Premium dark navy
  
  static const List<Color> gradientColors = [
    Color(0xFF3A4A6B),
    Color(0xFF202C4D),
  ];
  
  static const Color scaffoldBackgroundColor = Color(0xFFFAFAFA);
  
  static final ThemeData lightTheme = ThemeData(
    primaryColor: primaryColor,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: const Color(0xFF202C4D),
      surface: scaffoldBackgroundColor,
    ),
    useMaterial3: true,
  );

  static void show(BuildContext context, SnackBar snackBar) {
    final mediaQuery = MediaQuery.of(context);
    final bottomMargin = mediaQuery.size.height > 0
        ? (mediaQuery.size.height / 2 - 40)
        : 300.0;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
            child: snackBar.content,
          ),
        ),
        backgroundColor: snackBar.backgroundColor ?? primaryColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1), // Always vanish in 1 second!
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 40,
          right: 40,
        ),
      ),
    );
  }
}