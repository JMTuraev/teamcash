import 'package:flutter/material.dart';

ThemeData buildTeamCashTheme() {
  const canvas = Color(0xFFF7F8FF);
  const surface = Color(0xFFFFFFFF);
  const primary = Color(0xFF5D6BFF);
  const secondary = Color(0xFF63D3BF);
  const tertiary = Color(0xFF1E285C);
  const outline = Color(0xFFE4E8F7);
  const surfaceTint = Color(0xFFF1F3FE);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        tertiary: tertiary,
        surface: surface,
        onSurface: const Color(0xFF20264D),
        outline: outline,
        primaryContainer: const Color(0xFFE9ECFF),
        secondaryContainer: const Color(0xFFE7FBF6),
        surfaceContainerHighest: surfaceTint,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: canvas,
  );

  final softShadow = [
    BoxShadow(
      color: const Color(0xFF4D5FBE).withValues(alpha: 0.10),
      blurRadius: 34,
      offset: const Offset(0, 18),
    ),
  ];

  return base.copyWith(
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: outline),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: colorScheme.onSurface,
        letterSpacing: -0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.14),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 82,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? primary : const Color(0xFF7A82A6),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? primary : const Color(0xFF7A82A6),
          size: 22,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE2E6F7),
        disabledForegroundColor: const Color(0xFF9EA8CA),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tertiary,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        side: const BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface.withValues(alpha: 0.92),
      hintStyle: const TextStyle(color: Color(0xFFA2A9C6)),
      labelStyle: const TextStyle(color: Color(0xFF7A82A6)),
      prefixIconColor: const Color(0xFF8D95B8),
      suffixIconColor: const Color(0xFF8D95B8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFFE66E7A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFFE66E7A), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xFFF5F7FF),
      selectedColor: colorScheme.primaryContainer,
      secondarySelectedColor: colorScheme.primaryContainer,
      labelStyle: const TextStyle(color: tertiary, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
        color: tertiary,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tertiary,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: outline,
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        color: tertiary,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: tertiary,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: tertiary,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: tertiary,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: tertiary,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        height: 1.5,
        color: const Color(0xFF515A7E),
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.45,
        color: const Color(0xFF626B8E),
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.4,
        color: const Color(0xFF7C84A5),
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: tertiary,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[
      _SoftShadowTheme(shadows: softShadow),
    ],
  );
}

class _SoftShadowTheme extends ThemeExtension<_SoftShadowTheme> {
  const _SoftShadowTheme({required this.shadows});

  final List<BoxShadow> shadows;

  @override
  ThemeExtension<_SoftShadowTheme> copyWith({List<BoxShadow>? shadows}) {
    return _SoftShadowTheme(shadows: shadows ?? this.shadows);
  }

  @override
  ThemeExtension<_SoftShadowTheme> lerp(
    covariant ThemeExtension<_SoftShadowTheme>? other,
    double t,
  ) {
    if (other is! _SoftShadowTheme) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}
