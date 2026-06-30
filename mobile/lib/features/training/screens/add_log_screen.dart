import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../data/training_models.dart';
import '../providers/training_provider.dart';

class AddLogScreen extends ConsumerStatefulWidget {
  const AddLogScreen({super.key});

  @override
  ConsumerState<AddLogScreen> createState() => _AddLogScreenState();
}

class _AddLogScreenState extends ConsumerState<AddLogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  String _sessionType = SessionType.practice;
  String? _intensity;

  @override
  void dispose() {
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null || duration <= 0) return;

    final ok = await ref.read(trainingLogsProvider.notifier).addLog(
          TrainingLogCreate(
            sessionType: _sessionType,
            durationMinutes: duration,
            intensity: _intensity,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );

    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trainingLogsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Session'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Session type ──────────────────────────────────────────
            Text('Session type', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _TypeSelector(
              selected: _sessionType,
              onChanged: (v) => setState(() => _sessionType = v),
            ),
            const SizedBox(height: 20),

            // ── Duration ──────────────────────────────────────────────
            Text('Duration (minutes)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'e.g. 60',
                suffixText: 'min',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Duration is required';
                }
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) {
                  return 'Enter a positive number of minutes';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── Intensity ─────────────────────────────────────────────
            Text('Intensity (optional)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _IntensitySelector(
              selected: _intensity,
              onChanged: (v) => setState(() => _intensity = v),
            ),
            const SizedBox(height: 20),

            // ── Notes ─────────────────────────────────────────────────
            Text('Notes (optional)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'How did the session go?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // ── Error ─────────────────────────────────────────────────
            if (state.submitError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  state.submitError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),

            // ── Submit ────────────────────────────────────────────────
            AppButton(
              label: 'Save Session',
              icon: Icons.check,
              isLoading: state.isSubmitting,
              onPressed: state.isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Session type selector ─────────────────────────────────────────────────────

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SessionType.all.map((type) {
        final isSelected = type == selected;
        return ChoiceChip(
          label: Text(SessionType.label(type)),
          selected: isSelected,
          selectedColor: AppColors.primary.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.onSurface,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: isSelected
                ? AppColors.primary
                : AppColors.outline,
          ),
          onSelected: (_) => onChanged(type),
        );
      }).toList(),
    );
  }
}

// ── Intensity selector ────────────────────────────────────────────────────────

class _IntensitySelector extends StatelessWidget {
  const _IntensitySelector({
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = {
      IntensityLevel.low:    AppColors.success,
      IntensityLevel.medium: AppColors.warning,
      IntensityLevel.high:   AppColors.error,
    };

    return Wrap(
      spacing: 8,
      children: [
        // "None" chip to clear intensity.
        ChoiceChip(
          label: const Text('None'),
          selected: selected == null,
          selectedColor: AppColors.surfaceVariant,
          side: BorderSide(
            color: selected == null
                ? AppColors.onSurfaceVariant
                : AppColors.outline,
          ),
          onSelected: (_) => onChanged(null),
        ),
        ...IntensityLevel.all.map((level) {
          final isSelected = level == selected;
          final color = colors[level] ?? AppColors.primary;
          return ChoiceChip(
            label: Text(IntensityLevel.label(level)),
            selected: isSelected,
            selectedColor: color.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected ? color : AppColors.onSurface,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            side: BorderSide(
              color: isSelected ? color : AppColors.outline,
            ),
            onSelected: (_) => onChanged(level),
          );
        }),
      ],
    );
  }
}
