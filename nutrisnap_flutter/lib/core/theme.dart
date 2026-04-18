import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color bgPrimary = Color(0xFFF8F9FB);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  
  // Glassmorphism Colors
  static const Color glassBg = Color(0xB3FFFFFF); // rgba(255, 255, 255, 0.7)
  static const Color glassBorder = Color(0x66FFFFFF); // rgba(255, 255, 255, 0.4)
  static const Color glassCardBg = Color(0x99FFFFFF); // rgba(255, 255, 255, 0.6)
  static const Color glassCardBorder = Color(0x80FFFFFF); // rgba(255, 255, 255, 0.5)

  // Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x121F2687), // rgba(31, 38, 135, 0.07)
      offset: Offset(0, 8),
      blurRadius: 32,
      spreadRadius: 0,
    )
  ];

  static const List<BoxShadow> iosShadow = [
    BoxShadow(
      color: Color(0x1A000000), // rgba(0, 0, 0, 0.1)
      offset: Offset(0, 10),
      blurRadius: 30,
      spreadRadius: -10,
    )
  ];

  static const List<BoxShadow> glassCardShadow = [
    BoxShadow(
      color: Color(0x0D000000), // rgba(0, 0, 0, 0.05)
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    )
  ];

  // Typography
  static TextTheme get textTheme {
    return GoogleFonts.interTextTheme().apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );
  }

  // ThemeData
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bgPrimary,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        background: bgPrimary,
      ),
    );
  }

  // BoxDecorations for Glassmorphism
  static BoxDecoration get glassDecoration {
    return BoxDecoration(
      color: glassBg,
      border: Border.all(color: glassBorder, width: 1),
      boxShadow: cardShadow,
    );
  }

  static BoxDecoration get glassCardDecoration {
    return BoxDecoration(
      color: glassCardBg,
      border: Border.all(color: glassCardBorder, width: 1),
      boxShadow: glassCardShadow,
    );
  }
}
