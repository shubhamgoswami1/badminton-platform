import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand — shuttlecock green
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF60AD5E);
  static const Color primaryDark = Color(0xFF005005);

  // Accent — court blue
  static const Color secondary = Color(0xFF1565C0);
  static const Color secondaryLight = Color(0xFF5E92F3);
  static const Color secondaryDark = Color(0xFF003C8F);

  // Status
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57C00);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF0277BD);

  // Neutrals
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  static const Color outline = Color(0xFFE0E0E0);
  static const Color onSurface = Color(0xFF212121);
  static const Color onSurfaceVariant = Color(0xFF757575);
  static const Color disabled = Color(0xFFBDBDBD);

  // Tournament status chips
  static const Color statusDraft = Color(0xFF9E9E9E);
  static const Color statusOpen = Color(0xFF2E7D32);
  static const Color statusClosed = Color(0xFFF57C00);
  static const Color statusInProgress = Color(0xFF1565C0);
  static const Color statusCompleted = Color(0xFF6A1B9A);
  static const Color statusCancelled = Color(0xFFC62828);
}
