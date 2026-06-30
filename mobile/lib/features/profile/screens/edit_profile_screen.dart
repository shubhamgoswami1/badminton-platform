import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';
import '../providers/profile_provider.dart';

const _skillLevels = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'PROFESSIONAL'];
const _playStyles = ['SINGLES', 'DOUBLES', 'BOTH'];

/// Edit-profile sheet — pre-populated from [existing] profile.
/// Can be pushed as a full-screen route or shown as a bottom sheet.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.existing});

  final PlayerProfile existing;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _bioCtrl;

  String? _selectedSkill;
  String? _selectedStyle;

  double? _latitude;
  double? _longitude;
  bool _fetchingLocation = false;
  String? _locationLabel;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p.displayName);
    _cityCtrl = TextEditingController(text: p.city ?? '');
    _bioCtrl = TextEditingController(text: p.bio ?? '');
    _selectedSkill = p.skillLevel;
    _selectedStyle = p.playStyle;
    _latitude = p.latitude;
    _longitude = p.longitude;
    if (p.latitude != null && p.longitude != null) {
      _locationLabel =
          '${p.latitude!.toStringAsFixed(4)}, ${p.longitude!.toStringAsFixed(4)}';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _detectLocation() async {
    setState(() {
      _fetchingLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied.'),
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
          const SnackBar(content: Text('Could not get location.')),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final city =
        _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim();
    final bio = _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim();

    final req = ProfileUpdateRequest(
      displayName: _nameCtrl.text.trim(),
      city: city,
      skillLevel: _selectedSkill,
      playStyle: _selectedStyle,
      bio: bio,
      latitude: _latitude,
      longitude: _longitude,
    );

    final ok = await ref.read(profileProvider.notifier).save(req);
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSaving = ref.watch(profileProvider).isSaving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: isSaving ? null : _submit,
            child: isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            // Display name
            AppTextField(
              controller: _nameCtrl,
              label: 'Display Name *',
              maxLength: 80,
              autofocus: true,
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

            // City
            AppTextField(
              controller: _cityCtrl,
              label: 'City',
              hint: 'e.g. Mumbai',
              maxLength: 80,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            // Location row
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
            const SizedBox(height: 20),

            // Bio
            AppTextField(
              controller: _bioCtrl,
              label: 'Bio',
              hint: 'Tell other players about yourself',
              maxLength: 500,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 28),

            // Skill level
            Text('Skill Level', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            _ChipGroup(
              options: _skillLevels,
              selected: _selectedSkill,
              onSelected: (v) => setState(() => _selectedSkill = v),
            ),
            const SizedBox(height: 24),

            // Play style
            Text('Play Style', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            _ChipGroup(
              options: _playStyles,
              selected: _selectedStyle,
              onSelected: (v) => setState(() => _selectedStyle = v),
            ),
            const SizedBox(height: 40),

            AppButton(
              label: 'Save Changes',
              isLoading: isSaving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

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
