import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.surfaceVariant,

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),

        // Bottom navigation (M3 NavigationBar)
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          elevation: 8,
          height: 68,
          indicatorColor: AppColors.primary.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 24,
            );
          }),
        ),

        // Cards
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),

        // Buttons
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),

        // Input
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: AppColors.disabled, fontSize: 14),
        ),

        // Chip
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        ),

        // TabBar — white labels/indicator when inside an AppBar
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          indicatorSize: TabBarIndicatorSize.label,
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: AppColors.outline,
          thickness: 1,
          space: 0,
        ),

        // Typography
        textTheme: _textTheme,
      );

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.onSurface),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.onSurface),
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface),
    headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface),
    titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface),
    titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
    titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.onSurface),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.onSurface),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface),
    labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant),
  );
}
