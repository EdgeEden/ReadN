import 'package:flutter/material.dart';

enum ReadingMode {
  light,
  sepia,
  dark,
}

class HighlightColorItem {
  final String hex;
  final String label;
  final Color color;

  const HighlightColorItem({
    required this.hex,
    required this.label,
    required this.color,
  });
}

class AppTheme {
  // Highlight palette
  static const List<HighlightColorItem> highlightColors = [
    HighlightColorItem(hex: "#FFE066", label: "日光金", color: Color(0xFFFFE066)),
    HighlightColorItem(hex: "#69DB7C", label: "青翠绿", color: Color(0xFF69DB7C)),
    HighlightColorItem(hex: "#FFA8A8", label: "樱花粉", color: Color(0xFFFFA8A8)),
    HighlightColorItem(hex: "#D0BFFF", label: "丁香紫", color: Color(0xFFD0BFFF)),
    HighlightColorItem(hex: "#74C0FC", label: "晴空蓝", color: Color(0xFF74C0FC)),
    HighlightColorItem(hex: "#FF922B", label: "落日橙", color: Color(0xFFFF922B)),
  ];

  static Color parseHexColor(String hexString, {double alpha = 1.0}) {
    final buffer = StringBuffer();
    if (hexString.startsWith('#')) {
      hexString = hexString.substring(1);
    }
    if (hexString.length == 6) {
      buffer.write('ff');
      buffer.write(hexString);
    } else if (hexString.length == 8) {
      buffer.write(hexString);
    } else {
      return const Color(0xFFFFE066).withValues(alpha: alpha);
    }
    return Color(int.parse(buffer.toString(), radix: 16)).withValues(alpha: alpha);
  }

  // Adjusted color for Dark Mode so highlights stay true to color under inversion
  static Color getHighlightColorForRendering(String hexString, {bool isDark = false, double alpha = 0.45}) {
    if (!isDark) {
      return parseHexColor(hexString, alpha: alpha);
    }
    final clean = hexString.toUpperCase().replaceAll('#', '');
    switch (clean) {
      case "FFE066":
        return const Color(0xFF000AB2).withValues(alpha: 0.65);
      case "69DB7C":
        return const Color(0xFF921095).withValues(alpha: 0.65);
      case "FFA8A8":
        return const Color(0xFF004E5D).withValues(alpha: 0.65);
      case "D0BFFF":
        return const Color(0xFF163200).withValues(alpha: 0.65);
      case "74C0FC":
        return const Color(0xFF853100).withValues(alpha: 0.65);
      case "FF922B":
        return const Color(0xFF0069FE).withValues(alpha: 0.65);
      default:
        return parseHexColor(hexString, alpha: 0.65);
    }
  }

  // Color filter for Dark Mode: Invert white background to dark slate (#0F172A), black text to light white (#E2E8F0)
  static const ColorFilter darkPdfColorFilter = ColorFilter.matrix([
    -0.827,  0.000,  0.000, 0.0, 226.0,
     0.000, -0.820,  0.000, 0.0, 232.0,
     0.000,  0.000, -0.776, 0.0, 240.0,
     0.000,  0.000,  0.000, 1.0,   0.0,
  ]);

  // Inverse Color filter for Dark Mode (to restore original colors for context menus/overlays)
  static const ColorFilter darkPdfInverseColorFilter = ColorFilter.matrix([
    -1.20919,  0.0,       0.0,      0.0, 273.277,
     0.0,     -1.21951,   0.0,      0.0, 282.927,
     0.0,      0.0,      -1.28866,  0.0, 309.278,
     0.0,      0.0,       0.0,      1.0,   0.0,
  ]);

  // Color filter for Sepia Mode: Warm amber paper tone
  static const ColorFilter sepiaPdfColorFilter = ColorFilter.matrix([
    0.92, 0.05, 0.02, 0.0,  18.0,
    0.05, 0.88, 0.02, 0.0,  12.0,
    0.02, 0.05, 0.72, 0.0,   0.0,
    0.00, 0.00, 0.00, 1.0,   0.0,
  ]);

  // Inverse Color filter for Sepia Mode
  static const ColorFilter sepiaPdfInverseColorFilter = ColorFilter.matrix([
    1.087, 0.0,   0.0,   0.0, -19.565,
    0.0,   1.136, 0.0,   0.0, -13.636,
    0.0,   0.0,   1.389, 0.0,   0.0,
    0.0,   0.0,   0.0,   1.0,   0.0,
  ]);

  // Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F46E5), // Indigo
        brightness: Brightness.light,
        surface: const Color(0xFFF8FAFC),
        primary: const Color(0xFF4F46E5),
        secondary: const Color(0xFF0EA5E9),
      ),
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        color: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF4F46E5),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  // Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
        surface: const Color(0xFF1E293B),
        primary: const Color(0xFF818CF8),
        secondary: const Color(0xFF38BDF8),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1120),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        color: const Color(0xFF1E293B),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        foregroundColor: Color(0xFFF8FAFC),
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  // Sepia / Eye-Care Theme for Reader
  static ThemeData get sepiaTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD97706),
        brightness: Brightness.light,
        surface: const Color(0xFFF4ECD8),
        primary: const Color(0xFFB45309),
        secondary: const Color(0xFFD97706),
      ),
      scaffoldBackgroundColor: const Color(0xFFE8DCC4),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD6C8AF)),
        ),
        color: const Color(0xFFFBF7EE),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4ECD8),
        foregroundColor: Color(0xFF451A03),
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  // Reader Canvas background colors
  static Color getReaderBgColor(ReadingMode mode) {
    switch (mode) {
      case ReadingMode.light:
        return const Color(0xFFF1F5F9);
      case ReadingMode.sepia:
        return const Color(0xFFE8DCC4);
      case ReadingMode.dark:
        return const Color(0xFF0B1120);
    }
  }

  // Reader Page background colors
  static Color getReaderPageBgColor(ReadingMode mode) {
    switch (mode) {
      case ReadingMode.light:
        return Colors.white;
      case ReadingMode.sepia:
        return const Color(0xFFFAF3E3);
      case ReadingMode.dark:
        return const Color(0xFF0F172A);
    }
  }
}
