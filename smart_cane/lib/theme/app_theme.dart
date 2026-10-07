import 'package:flutter/material.dart';

class AppThemeColors {
  final Color background;
  final Color cardColor;
  final Color primaryGreen;
  final Color warningRed;
  final Color iconBlue;
  final Color textPrimary;
  final Color textSecondary;

  const AppThemeColors({
    required this.background,
    required this.cardColor,
    required this.primaryGreen,
    required this.warningRed,
    required this.iconBlue,
    required this.textPrimary,
    required this.textSecondary,
  });
}

class AppTheme {
  // --- DARK COLORS ---
  static const AppThemeColors darkColors = AppThemeColors(
    background: Color(0xFF121212),
    cardColor: Color(0xFF1E1E1E),
    primaryGreen: Color(0xFF00C853),
    warningRed: Color(0xFFFF3D00),
    iconBlue: Color(0xFF29B6F6),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
  );

  // --- LIGHT COLORS ---
  static const AppThemeColors lightColors = AppThemeColors(
    background: Color(0xFFF5F5F7), // Màu xám nhạt tinh tế kiểu Apple
    cardColor: Colors.white,
    primaryGreen: Color(0xFF00A040),
    warningRed: Color(0xFFD32F2F),
    iconBlue: Color(0xFF0288D1),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF8E8E93),
  );

  // Lấy màu hiện tại dựa vào ThemeMode
  static AppThemeColors colors(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkColors : lightColors;
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkColors.background,
      primaryColor: darkColors.primaryGreen,
      cardColor: darkColors.cardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: darkColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkColors.textPrimary),
        titleTextStyle: TextStyle(color: darkColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: darkColors.textPrimary),
        bodyMedium: TextStyle(color: darkColors.textSecondary),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightColors.background,
      primaryColor: lightColors.primaryGreen,
      cardColor: lightColors.cardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: lightColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: lightColors.textPrimary),
        titleTextStyle: TextStyle(color: lightColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: lightColors.textPrimary),
        bodyMedium: TextStyle(color: lightColors.textSecondary),
      ),
    );
  }
}
