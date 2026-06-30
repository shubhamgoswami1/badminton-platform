import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../providers/auth_provider.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _fullPhone => '+91${_phoneController.text.trim()}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ref.read(authProvider.notifier).requestOtp(_fullPhone);
      if (!mounted) return;
      context.push(AppRoutes.otp, extra: _fullPhone);
    } catch (_) {
      // Error already in state — displayed below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Enter your number'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  'What\'s your phone number?',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'We\'ll send you a one-time verification code.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 36),

                // Phone input row with +91 prefix
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Country code badge
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.outline),
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.surface,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '🇮🇳  +91',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          hintText: '98765 43210',
                          counterText: '',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().length < 10) {
                            return 'Enter a valid 10-digit number';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Error message
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      auth.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                AppButton(
                  label: 'Send OTP',
                  isLoading: auth.isLoading,
                  onPressed: auth.isLoading ? null : _submit,
                  icon: Icons.arrow_forward,
                ),

                const Spacer(),

                Text(
                  'Standard messaging rates may apply.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.disabled,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
