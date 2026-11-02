import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

/// Confirms an email address with a custom 6-digit code sent via Resend.
///
/// Validated against `account_otps` and sets `profiles.email_verified = true`.
class OtpScreen extends StatefulWidget {
  final String email;
  final String? kind;

  const OtpScreen({
    super.key,
    required this.email,
    this.kind,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 60;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  /// Rate-limits resends with 60-second cooldown.
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

  Future<void> _verify(String code) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyCustomOtp(email: widget.email, code: code);

    if (!mounted) return;
    if (ok) {
      final user = auth.user;
      if (user?.isStaff ?? false) {
        final kindParam = widget.kind != null && widget.kind!.isNotEmpty
            ? '?kind=${widget.kind}'
            : '';
        context.go('${AppConstants.routeOrgSetup}$kindParam');
      } else {
        context.go(AppConstants.routeHome);
      }
    } else {
      _controller.clear();
      _showError(auth.error ?? 'That code was not accepted.');
    }
  }

  Future<void> _resend() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendCustomOtp(widget.email);
    if (!mounted) return;

    if (ok) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A fresh 6-digit code has been sent to your email.'),
        ),
      );
    } else {
      _showError(auth.error ?? 'Could not send a new code.');
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
      appBar: AppBar(
        leading: AppBackButton(fallback: AppConstants.routeLogin),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Check your email', style: text.displaySmall),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: text.bodyMedium,
                      children: [
                        TextSpan(
                          text: 'We sent a ${AppConstants.otpLength}-digit '
                              'verification code to ',
                        ),
                        TextSpan(
                          text: widget.email,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Pinput(
                    controller: _controller,
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
                    onCompleted: busy ? null : _verify,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: busy ||
                            _controller.text.length < AppConstants.otpLength
                        ? null
                        : () => _verify(_controller.text),
                    child: busy
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: context.colors.onAccent,
                            ),
                          )
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: _secondsLeft > 0
                        ? Text(
                            'You can request a new code in $_secondsLeft s',
                            style: text.bodySmall,
                          )
                        : TextButton(
                            onPressed: busy ? null : _resend,
                            child: const Text('Send a new code'),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await context.read<AuthProvider>().signOut();
                              if (!context.mounted) return;
                              context.go(AppConstants.routeLogin);
                            },
                      child: Text(
                        'Use a different account or sign in',
                        style: text.bodySmall?.copyWith(color: colors.textLight),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
