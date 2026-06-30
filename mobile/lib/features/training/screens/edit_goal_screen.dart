import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../data/training_models.dart';
import '../providers/goals_provider.dart';

class EditGoalScreen extends ConsumerStatefulWidget {
  const EditGoalScreen({super.key, required this.goal});

  final TrainingGoal goal;

  @override
  ConsumerState<EditGoalScreen> createState() => _EditGoalScreenState();
}

class _EditGoalScreenState extends ConsumerState<EditGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  DateTime? _targetDate;
  late String _status;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.goal.title);
    _descController =
        TextEditingController(text: widget.goal.description ?? '');
    _targetDate = widget.goal.targetDate;
    _status = widget.goal.status;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ??
          DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await ref.read(goalsProvider.notifier).updateGoal(
          widget.goal.id,
          TrainingGoalUpdate(
            title: _titleController.text.trim(),
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
            targetDate: _targetDate,
            status: _status,
          ),
        );

    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goalsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Goal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Goal title', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              maxLength: 120,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 20),

            Text('Description (optional)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            Text('Target date (optional)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _DatePickerTile(
              date: _targetDate,
              onTap: _pickDate,
              onClear: () => setState(() => _targetDate = null),
            ),
            const SizedBox(height: 20),

            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _StatusSelector(
              selected: _status,
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 24),

            if (state.submitError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  state.submitError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),

            AppButton(
              label: 'Save Changes',
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

// ── Status selector ───────────────────────────────────────────────────────────

class _StatusSelector extends StatelessWidget {
  const _StatusSelector({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const colors = {
      GoalStatus.active:    AppColors.primary,
      GoalStatus.achieved:  AppColors.success,
      GoalStatus.abandoned: AppColors.onSurfaceVariant,
    };

    return Wrap(
      spacing: 8,
      children: GoalStatus.all.map((status) {
        final isSelected = status == selected;
        final color = colors[status] ?? AppColors.primary;
        return ChoiceChip(
          label: Text(GoalStatus.label(status)),
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
          onSelected: (_) => onChanged(status),
        );
      }).toList(),
    );
  }
}

// ── Date picker tile ──────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                date == null ? 'No target date' : _fmt(date!),
                style: TextStyle(
                  color: date == null
                      ? AppColors.onSurfaceVariant
                      : AppColors.onSurface,
                ),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 18, color: AppColors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

String _fmt(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
