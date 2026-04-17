import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';

/// Welcome / login landing screen.
/// Actual OTP flow is implemented in P1 — this is the scaffold.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // Icon
              Center(
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.sports_tennis,
                    size: 60,
                    color: AppColors.primary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Badminton Platform',
                style: theme.textTheme.displayMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Organise tournaments, track training,\nand discover players in your city.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 3),

              // Feature highlights
              _FeatureRow(
                icon: Icons.emoji_events_outlined,
                text: 'Run knockout & round-robin tournaments',
              ),
              const SizedBox(height: 14),
              _FeatureRow(
                icon: Icons.fitness_center_outlined,
                text: 'Log training sessions and set goals',
              ),
              const SizedBox(height: 14),
              _FeatureRow(
                icon: Icons.people_outline,
                text: 'Discover players and venues near you',
              ),

              const Spacer(flex: 2),

              AppButton(
                label: 'Continue with Phone',
                onPressed: () {
                  // TODO(P1): navigate to phone entry screen
                  // For now, bypass auth in dev by going straight to home
                  context.go(AppRoutes.home);
                },
                icon: Icons.phone_android,
              ),

              const SizedBox(height: 16),
              Text(
                'We\'ll send you a one-time verification code.\nNo passwords required.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.disabled,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
