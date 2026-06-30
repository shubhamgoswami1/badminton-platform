import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/profile_repository.dart';
import '../providers/profile_provider.dart';

// ── Skill / Play-style constants ───────────────────────────────────────────

const _skillLevels = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'PROFESSIONAL'];
const _playStyles = ['SINGLES', 'DOUBLES', 'BOTH'];

// ── Onboarding screen ──────────────────────────────────────────────────────

/// Shown once, right after a user's very first login.
/// Collects display name, city, optional GPS, skill level, and play style.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  String? _selectedSkill;
  String? _selectedStyle;

  // Location state
  double? _latitude;
  double? _longitude;
  bool _fetchingLocation = false;
  String? _locationLabel; // e.g. "19.0760, 72.8777"

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  // ── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _detectLocation() async {
    setState(() {
      _fetchingLocation = true;
      _locationLabel = null;
    });

    try {
      // Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied. Enter your city manually.'),
            ),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = pos.latitude;
          _longitude = pos.longitude;
          _locationLabel =
              '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get location. Enter your city manually.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final city = _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim();

    final req = ProfileUpdateRequest(
      displayName: _nameCtrl.text.trim(),
      city: city,
      skillLevel: _selectedSkill,
      playStyle: _selectedStyle,
      latitude: _latitude,
      longitude: _longitude,
    );

    final ok = await ref.read(profileProvider.notifier).save(req);
    if (!ok || !mounted) return;

    // Mark first-login complete so the router stops redirecting to onboarding.
    ref.read(authProvider.notifier).markOnboardingComplete();
    context.go(AppRoutes.home);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileState = ref.watch(profileProvider);
    final isSaving = profileState.isSaving;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            children: [
              // Header
              Text(
                'Welcome! 🏸',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set up your player profile to get started.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Display name (required)
              AppTextField(
                controller: _nameCtrl,
                label: 'Display Name *',
                hint: 'How you appear to other players',
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Display name is required';
                  }
                  if (v.trim().length < 2) return 'At least 2 characters';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // City (optional)
              AppTextField(
                controller: _cityCtrl,
                label: 'City',
                hint: 'e.g. Mumbai',
                maxLength: 80,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),

              // GPS location button
              _LocationRow(
                isFetching: _fetchingLocation,
                locationLabel: _locationLabel,
                onDetect: _detectLocation,
                onClear: () => setState(() {
                  _latitude = null;
                  _longitude = null;
                  _locationLabel = null;
                }),
              ),
              const SizedBox(height: 28),

              // Skill level chips
              const _SectionLabel(label: 'Skill Level'),
              const SizedBox(height: 10),
              _ChipGroup(
                options: _skillLevels,
                selected: _selectedSkill,
                onSelected: (v) => setState(() => _selectedSkill = v),
              ),
              const SizedBox(height: 24),

              // Play style chips
              const _SectionLabel(label: 'Play Style'),
              const SizedBox(height: 10),
              _ChipGroup(
                options: _playStyles,
                selected: _selectedStyle,
                onSelected: (v) => setState(() => _selectedStyle = v),
              ),
              const SizedBox(height: 40),

              // Submit
              AppButton(
                label: 'Get Started',
                isLoading: isSaving,
                onPressed: _submit,
              ),

              // Skip
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          ref
                              .read(authProvider.notifier)
                              .markOnboardingComplete();
                          context.go(AppRoutes.home);
                        },
                  child: Text(
                    'Skip for now',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options.map((opt) {
        final isSelected = opt == selected;
        return ChoiceChip(
          label: Text(_label(opt)),
          selected: isSelected,
          onSelected: (_) => onSelected(isSelected ? null : opt),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.onSurface,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  String _label(String raw) {
    // Convert "BEGINNER" → "Beginner"
    if (raw.isEmpty) return raw;
    return raw[0] + raw.substring(1).toLowerCase();
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.isFetching,
    required this.locationLabel,
    required this.onDetect,
    required this.onClear,
  });

  final bool isFetching;
  final String? locationLabel;
  final VoidCallback onDetect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (locationLabel != null) {
      return Row(
        children: [
          const Icon(Icons.location_on, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              locationLabel!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.primary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClear,
            tooltip: 'Remove location',
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: isFetching ? null : onDetect,
      icon: isFetching
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location, size: 18),
      label: Text(isFetching ? 'Detecting…' : 'Use my location'),
    );
  }
}
