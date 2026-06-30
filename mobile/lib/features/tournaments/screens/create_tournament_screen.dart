import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/tournament_models.dart';
import '../providers/tournament_provider.dart';

class CreateTournamentScreen extends ConsumerStatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  ConsumerState<CreateTournamentScreen> createState() =>
      _CreateTournamentScreenState();
}

class _CreateTournamentScreenState
    extends ConsumerState<CreateTournamentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _maxParticipantsCtrl = TextEditingController();

  String _format = TournamentFormat.knockout;
  String _matchFormat = MatchFormat.bestOf3;
  String _playType = PlayType.singles;

  DateTime? _registrationDeadline;
  DateTime? _startsAt;

  double? _latitude;
  double? _longitude;
  bool _fetchingLocation = false;
  String? _locationLabel;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _cityCtrl.dispose();
    _descCtrl.dispose();
    _maxParticipantsCtrl.dispose();
    super.dispose();
  }

  // ── Location detection ────────────────────────────────────────────────

  Future<void> _detectLocation() async {
    setState(() {
      _fetchingLocation = true;
      _locationLabel = null;
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
              content:
                  Text('Location permission denied. Enter your city manually.'),
            ),
          );
        }
        setState(() => _fetchingLocation = false);
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
          _fetchingLocation = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _fetchingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location.')),
        );
      }
    }
  }

  void _clearLocation() => setState(() {
        _latitude = null;
        _longitude = null;
        _locationLabel = null;
      });

  // ── Date pickers ──────────────────────────────────────────────────────

  Future<void> _pickDate({required bool isRegistration}) async {
    final now = DateTime.now();
    final initial = isRegistration
        ? (_registrationDeadline ?? now)
        : (_startsAt ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isRegistration) {
        _registrationDeadline = picked;
      } else {
        _startsAt = picked;
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final maxP = _maxParticipantsCtrl.text.isNotEmpty
        ? int.tryParse(_maxParticipantsCtrl.text)
        : null;

    final req = CreateTournamentRequest(
      title: _titleCtrl.text.trim(),
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      format: _format,
      matchFormat: _matchFormat,
      playType: _playType,
      maxParticipants: maxP,
      registrationDeadline:
          _registrationDeadline?.toUtc().toIso8601String(),
      startsAt: _startsAt?.toUtc().toIso8601String(),
      latitude: _latitude,
      longitude: _longitude,
    );

    final ok = await ref
        .read(createTournamentProvider.notifier)
        .submit(req);

    if (!mounted) return;

    if (ok) {
      final created = ref.read(createTournamentProvider).created;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tournament created!'),
          backgroundColor: AppColors.success,
        ),
      );
      // Refresh hosted list and navigate to the new tournament's detail.
      ref.read(myHostedProvider.notifier).reload();
      if (created != null) {
        context.pushReplacement(AppRoutes.tournamentDetailPath(created.id));
      } else {
        context.pop();
      }
    }
    // Error is shown inline.
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createTournamentProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Tournament')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ───────────────────────────────────────────────
              AppTextField(
                controller: _titleCtrl,
                label: 'Title *',
                hint: 'e.g. City Open 2026',
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // ── Format dropdowns ────────────────────────────────────
              const _SectionLabel(label: 'Tournament Format'),
              const SizedBox(height: 8),
              _DropdownRow(
                children: [
                  Expanded(
                    child: _LabeledDropdown<String>(
                      label: 'Format',
                      value: _format,
                      items: TournamentFormat.all,
                      labelBuilder: TournamentFormat.label,
                      onChanged: (v) => setState(() => _format = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LabeledDropdown<String>(
                      label: 'Play Type',
                      value: _playType,
                      items: PlayType.all,
                      labelBuilder: PlayType.label,
                      onChanged: (v) => setState(() => _playType = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _LabeledDropdown<String>(
                label: 'Match Format',
                value: _matchFormat,
                items: MatchFormat.all,
                labelBuilder: MatchFormat.label,
                onChanged: (v) => setState(() => _matchFormat = v!),
              ),
              const SizedBox(height: 20),

              // ── Location ────────────────────────────────────────────
              const _SectionLabel(label: 'Location (optional)'),
              const SizedBox(height: 8),
              AppTextField(
                controller: _cityCtrl,
                label: 'City',
                hint: 'e.g. Mumbai',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              _LocationButton(
                isLoading: _fetchingLocation,
                label: _locationLabel,
                onDetect: _detectLocation,
                onClear: _clearLocation,
              ),
              const SizedBox(height: 20),

              // ── Capacity ────────────────────────────────────────────
              AppTextField(
                controller: _maxParticipantsCtrl,
                label: 'Max Participants (optional)',
                hint: 'e.g. 16',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = int.tryParse(v);
                  if (n == null || n < 2) return 'Must be at least 2';
                  if (n > 1024) return 'Cannot exceed 1024';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Dates ───────────────────────────────────────────────
              const _SectionLabel(label: 'Dates (optional)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DatePickerTile(
                      label: 'Registration closes',
                      date: _registrationDeadline,
                      onTap: () => _pickDate(isRegistration: true),
                      onClear: () => setState(() => _registrationDeadline = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DatePickerTile(
                      label: 'Starts on',
                      date: _startsAt,
                      onTap: () => _pickDate(isRegistration: false),
                      onClear: () => setState(() => _startsAt = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Description ─────────────────────────────────────────
              AppTextField(
                controller: _descCtrl,
                label: 'Description (optional)',
                hint: 'Rules, prizes, venue details…',
                maxLength: 500,
                keyboardType: TextInputType.multiline,
              ),

              // ── Error ────────────────────────────────────────────────
              if (createState.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    createState.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ── Submit ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Create Tournament',
                  icon: Icons.emoji_events_outlined,
                  isLoading: createState.isSubmitting,
                  onPressed: _submit,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable sub-widgets ───────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppColors.onSurfaceVariant),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(children: children);
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // ignore: deprecated_member_use
      value: value, // controlled: always tracks parent setState
      decoration: InputDecoration(labelText: label),
      items: items
          .map((e) => DropdownMenuItem<T>(
                value: e,
                child: Text(labelBuilder(e)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({
    required this.isLoading,
    required this.label,
    required this.onDetect,
    required this.onClear,
  });

  final bool isLoading;
  final String? label;
  final VoidCallback onDetect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: isLoading ? null : onDetect,
      icon: isLoading
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location, size: 18),
      label: Text(isLoading ? 'Detecting…' : 'Pin GPS location'),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDate = date != null;
    final local = date?.toLocal();
    final formatted = local != null
        ? '${local.day}/${local.month}/${local.year}'
        : 'Not set';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasDate ? AppColors.primary : AppColors.outline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatted,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasDate
                          ? AppColors.onSurface
                          : AppColors.disabled,
                      fontWeight:
                          hasDate ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
                if (hasDate)
                  GestureDetector(
                    onTap: onClear,
                    child: const Icon(Icons.close,
                        size: 14, color: AppColors.onSurfaceVariant),
                  )
                else
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppColors.disabled),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
