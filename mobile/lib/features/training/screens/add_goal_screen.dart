import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../data/training_models.dart';
import '../providers/goals_provider.dart';

class AddGoalScreen extends ConsumerStatefulWidget {
  const AddGoalScreen({super.key});

  @override
  ConsumerState<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends ConsumerState<AddGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _targetDate;

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
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await ref.read(goalsProvider.notifier).addGoal(
          TrainingGoalCreate(
            title: _titleController.text.trim(),
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
            targetDate: _targetDate,
          ),
        );

    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goalsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Goal')),
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
                hintText: 'e.g. Improve cross-court backhand',
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
                hintText: 'What does achieving this look like?',
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
              label: 'Save Goal',
              icon: Icons.flag_outlined,
              isLoading: state.isSubmitting,
              onPressed: state.isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
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
                date == null ? 'No target date' : _formatDate(date!),
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

String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
