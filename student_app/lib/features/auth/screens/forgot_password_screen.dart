import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../providers/auth_provider.dart';

enum _ResetStep { request, verifyAndReset, success }

/// Password reset via custom 6-digit OTP delivered through Resend.
/// Completely independent of Supabase magic links and default mailer.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _codeController = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _ResetStep _step = _ResetStep.request;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Timer? _timer;
  int _secondsLeft = 60;

  @override
  void dispose() {
    _email.dispose();
    _codeController.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(_email.text);

    if (!mounted) return;
    if (ok) {
      _startCooldown();
      setState(() => _step = _ResetStep.verifyAndReset);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A 6-digit reset code has been sent to your email.')),
      );
    } else {
      _showError(auth.error ?? 'Could not send reset code. Please try again.');
    }
  }

  Future<void> _resendCode() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(_email.text);

    if (!mounted) return;
    if (ok) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A fresh 6-digit reset code has been sent.')),
      );
    } else {
      _showError(auth.error ?? 'Could not resend code. Please wait a moment.');
    }
  }

  Future<void> _submitNewPassword() async {
    if (!(_resetFormKey.currentState?.validate() ?? false)) return;

    if (_codeController.text.trim().length < AppConstants.otpLength) {
      _showError('Please enter the full 6-digit verification code.');
      return;
    }

    if (_newPassword.text != _confirmPassword.text) {
      _showError('Passwords do not match.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.resetPasswordWithOtp(
      email: _email.text.trim(),
      code: _codeController.text.trim(),
      newPassword: _newPassword.text,
    );

    if (!mounted) return;
    if (ok) {
      setState(() => _step = _ResetStep.success);
    } else {
      _showError(auth.error ?? 'Could not reset password. Please check your code.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: context.colors.error),
    );
    context.read<AuthProvider>().clearError();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final busy = context.watch<AuthProvider>().busy;

    final defaultPin = PinTheme(
      width: 50,
      height: 56,
      textStyle: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
    );

    return Scaffold(
      appBar: AppBar(leading: AppBackButton(fallback: AppConstants.routeLogin)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStep(context, colors, text, busy, defaultPin),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(
    BuildContext context,
    AppThemeColors colors,
    TextTheme text,
    bool busy,
    PinTheme defaultPin,
  ) {
    switch (_step) {
      case _ResetStep.request:
        return Form(
          key: _emailFormKey,
          child: Column(
            key: const ValueKey('step_request'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset your password', style: text.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Enter your account email. We will send a 6-digit verification code to reset your password.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 28),
              CustomTextField(
                controller: _email,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _sendCode(),
                validator: AppValidators.validateEmail,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: busy ? null : _sendCode,
                child: busy
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.onAccent,
                        ),
                      )
                    : const Text('Send verification code'),
              ),
            ],
          ),
        );

      case _ResetStep.verifyAndReset:
        return Form(
          key: _resetFormKey,
          child: Column(
            key: const ValueKey('step_verify'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter reset code', style: text.displaySmall),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: text.bodyMedium,
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to '),
                    TextSpan(
                      text: _email.text.trim(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Pinput(
                controller: _codeController,
                length: AppConstants.otpLength,
                autofocus: true,
                defaultPinTheme: defaultPin,
                focusedPinTheme: defaultPin.copyWith(
                  decoration: defaultPin.decoration!.copyWith(
                    border: Border.all(color: colors.accent, width: 1.8),
                  ),
                ),
                submittedPinTheme: defaultPin.copyWith(
                  decoration: defaultPin.decoration!.copyWith(
                    color: colors.infoLight,
                    border: Border.all(color: colors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              CustomTextField(
                controller: _newPassword,
                label: 'New password',
                hint: 'At least 8 characters',
                obscureText: _obscurePassword,
                prefixIcon: Icons.lock_outline_rounded,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.length < 8)
                    ? 'Use at least 8 characters'
                    : null,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: colors.textLight,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _confirmPassword,
                label: 'Confirm new password',
                hint: 'Re-enter your password',
                obscureText: _obscureConfirm,
                prefixIcon: Icons.lock_outline_rounded,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitNewPassword(),
                validator: (v) =>
                    (v != _newPassword.text) ? 'Passwords do not match' : null,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: colors.textLight,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: busy ? null : _submitNewPassword,
                child: busy
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.onAccent,
                        ),
                      )
                    : const Text('Reset password'),
              ),
              const SizedBox(height: 16),
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in $_secondsLeft s',
                        style: text.bodySmall,
                      )
                    : TextButton(
                        onPressed: busy ? null : _resendCode,
                        child: const Text('Resend code'),
                      ),
              ),
              Center(
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => _step = _ResetStep.request),
                  child: Text(
                    'Change email address',
                    style: text.bodySmall?.copyWith(color: colors.textLight),
                  ),
                ),
              ),
            ],
          ),
        );

      case _ResetStep.success:
        return Column(
          key: const ValueKey('step_success'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 64, color: colors.success),
            const SizedBox(height: 20),
            Text(
              'Password updated',
              style: text.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your password has been reset successfully. You can now sign in with your new password.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => context.go(AppConstants.routeLogin),
              child: const Text('Sign in now'),
            ),
          ],
        );
    }
  }
}
