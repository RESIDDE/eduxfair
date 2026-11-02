import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_border.dart';
import '../../../core/widgets/material_surface.dart';
import '../widgets/auth_scaffold.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _country;
  bool _obscure = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      _showError('Please accept the terms to continue.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      email: _email.text,
      password: _password.text,
      fullName: _name.text,
      country: _country,
    );

    if (!mounted) return;
    if (!ok) {
      _showError(auth.error ?? 'Could not create your account.');
      return;
    }

    if (!mounted) return;
    context.push(
      '${AppConstants.routeOtp}?email=${Uri.encodeComponent(_email.text.trim())}',
    );
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

    return AuthScaffold(
      leading: const AppBackButton(fallback: AppConstants.routeSignup),
      title: 'Create your passport',
      subtitle:
          'Free, and it takes a few minutes. You decide which '
          'institutions ever see it.',
      footer: AuthFooterLink(
        question: 'Already registered?',
        action: 'Sign in',
        onTap: busy ? null : () => context.go(AppConstants.routeLogin),
      ),
      children: [
        GradientBorder(
          radius: 20,
          child: MaterialSurface(
            borderRadius: BorderRadius.circular(18.5),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CustomTextField(
                      controller: _name,
                      label: 'Full name',
                      hint: 'As it appears on your documents',
                      prefixIcon: Icons.person_outline_rounded,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Enter your full name'
                          : null,
                    ),
                    const SizedBox(height: 16),
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
                    DropdownButtonFormField<String>(
                      initialValue: _country,
                      decoration: const InputDecoration(
                        labelText: 'Where are you applying from?',
                        prefixIcon: Icon(Icons.public_rounded, size: 20),
                      ),
                      items: AppConstants.homeCountries.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _country = v),
                      validator: (v) =>
                          v == null ? 'Choose your country' : null,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _password,
                      label: 'Password',
                      hint: 'At least 8 characters',
                      obscureText: _obscure,
                      prefixIcon: Icons.lock_outline_rounded,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'Use at least 8 characters'
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
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          onChanged: (v) =>
                              setState(() => _acceptedTerms = v ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I agree to the Terms of Service and Privacy '
                              'Policy. My passport stays private until I share '
                              'it with an institution.',
                              style: text.bodySmall?.copyWith(height: 1.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
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
                          : const Text('Create account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
