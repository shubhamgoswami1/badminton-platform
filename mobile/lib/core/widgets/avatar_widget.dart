import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular avatar that shows text initials when no image is available.
/// [initials] should be 1–2 characters (e.g. "AS" for "Alice Sharma").
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({
    super.key,
    required this.initials,
    this.radius = 44,
    this.backgroundColor,
    this.textColor,
  });

  final String initials;
  final double radius;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ??
        AppColors.primaryLight.withValues(alpha: 0.18);
    final fg = textColor ?? AppColors.primary;

    // Pick a font size proportional to the radius so it never overflows.
    final fontSize = radius * 0.70;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: theme.textTheme.headlineLarge?.copyWith(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
