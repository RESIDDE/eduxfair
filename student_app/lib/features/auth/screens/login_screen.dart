import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/app_logo.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(
      email: _email.text,
      password: _password.text,
    );

    if (!mounted) return;
    if (ok) {
      if (auth.user?.isStaff ?? false) {
        context.go(AppConstants.routeOrgHome);
      } else {
        context.go(AppConstants.routeFeed);
      }
    } else {
      _showError(auth.error ?? 'Could not sign in.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.colors.error,
      ),
    );
    context.read<AuthProvider>().clearError();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final busy = context.watch<AuthProvider>().busy;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              // The app also ships to web, where an unconstrained form stretches
              // across a desktop window and becomes unreadable.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: EduxfairLogo(
                        size: 64,
                        borderRadius: 18,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Welcome back', style: text.displaySmall),
                    const SizedBox(height: 8),
                    Text(
                      'Students, universities, colleges and embassies all '
                      'sign in here — we take you to the right place.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    CustomTextField(
                      controller: _email,
                      label: 'Email address',
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.mail_outline_rounded,
                      textInputAction: TextInputAction.next,
                      validator: AppValidators.validateEmail,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _password,
                      label: 'Password',
                      hint: 'Your password',
                      obscureText: _obscure,
                      prefixIcon: Icons.lock_outline_rounded,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password'
                          : null,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: colors.textLight,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => context.push(AppConstants.routeForgotPassword),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: context.colors.onAccent,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account?", style: text.bodyMedium),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => context.go(AppConstants.routeSignup),
                          child: const Text('Create one'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
