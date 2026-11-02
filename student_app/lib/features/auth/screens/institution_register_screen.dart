import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/step_header.dart';
import '../providers/auth_provider.dart';

/// Step one of institution sign-up: the person's account.
///
/// Step two is the listing itself ([InstitutionSetupScreen]), which the router
/// reaches on its own — a staff account with no institution has `needsSetup`
/// true, so there is nothing to navigate manually and nothing to get out of
/// step if sign-up is interrupted and resumed later.
///
/// The organisation kind is asked *here*, before the listing, because it is
/// what the next screen and the whole listing are shaped by: an embassy has
/// visa routes and no programs.
class InstitutionRegisterScreen extends StatefulWidget {
  const InstitutionRegisterScreen({super.key});

  @override
  State<InstitutionRegisterScreen> createState() =>
      _InstitutionRegisterScreenState();
}

class _InstitutionRegisterScreenState extends State<InstitutionRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _kind = 'university';
  bool _obscure = true;
  bool _acceptedTerms = false;

  /// Free mail providers. Not rejected — a small college really may run on one
  /// — but the verified badge is earned by proving control of a domain, so
  /// saying so now is kinder than at verification time.
  static const _freeProviders = {
    'gmail.com', 'yahoo.com', 'yahoo.co.uk', 'hotmail.com', 'outlook.com',
    'live.com', 'icloud.com', 'aol.com', 'protonmail.com', 'gmx.com',
    'yandex.com', 'mail.com', 'zoho.com',
  };

  String? get _domain {
    final at = _email.text.trim().toLowerCase().split('@');
    return at.length == 2 && at[1].contains('.') ? at[1] : null;
  }

  bool get _isFreeProvider {
    final d = _domain;
    return d != null && _freeProviders.contains(d);
  }

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
      _showError('Please confirm you can act for this organisation.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      email: _email.text,
      password: _password.text,
      fullName: _name.text,
      role: 'institution_member',
    );

    if (!mounted) return;
    if (!ok) {
      _showError(auth.error ?? 'Could not create your account.');
      return;
    }

    // Remembered because the two steps may be separated by email
    // confirmation: with `mailer_autoconfirm` off, sign-up returns no session,
    // the person leaves for their inbox, and the router sends them to step two
    // on their own afterwards — with no query parameter to carry this. Without
    // it an embassy would quietly be filed as a university.
    await _remember(_kind);

    if (!mounted) return;
    context.push(
      '${AppConstants.routeOtp}?email=${Uri.encodeComponent(_email.text.trim())}&kind=$_kind',
    );
  }

  static const _kindKey = 'pending_institution_kind';

  Future<void> _remember(String kind) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kindKey, kind);
    } catch (_) {
      // Not worth failing sign-up over: step two shows the dropdown anyway.
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

    return Scaffold(
      appBar: AppBar(leading: AppBackButton(fallback: AppConstants.routeSignup)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const StepHeader(step: 1, label: 'Your account'),
                    const SizedBox(height: 18),
                    Text('Set up your organisation', style: text.displaySmall),
                    const SizedBox(height: 8),
                    Text(
                      'First your own sign-in. Next you describe the '
                      'organisation itself — the page students read.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: const InputDecoration(
                        labelText: 'What kind of organisation?',
                        prefixIcon: Icon(Icons.apartment_outlined, size: 20),
                      ),
                      items: AppConstants.institutionKinds.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _kind = v ?? 'university'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.institutionKindBlurbs[_kind] ?? '',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _name,
                      label: 'Your full name',
                      hint: 'Who students are speaking to',
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
                      label: 'Work email',
                      hint: 'admissions@yourinstitution.edu',
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.mail_outline_rounded,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      validator: AppValidators.validateEmail,
                    ),
                    const SizedBox(height: 8),
                    _DomainNote(
                      domain: _domain,
                      isFreeProvider: _isFreeProvider,
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
                              'I am authorised to act for this organisation, '
                              'and I agree to the Terms of Service and '
                              'Privacy Policy. I understand students decide '
                              'who sees their passport.',
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
                                color: colors.onAccent,
                              ),
                            )
                          : const Text('Continue'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Applying as a student?', style: text.bodyMedium),
                        TextButton(
                          onPressed: busy
                              ? null
                              // Back to the chooser, then into the other
                              // form: `go` straight across left that form's
                              // arrow with nothing to pop.
                              : () => context.go(AppConstants.routeSignup),
                          child: const Text('Create a passport'),
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

/// What the work email buys, said at the moment it is typed.
class _DomainNote extends StatelessWidget {
  final String? domain;
  final bool isFreeProvider;

  const _DomainNote({required this.domain, required this.isFreeProvider});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final (icon, colour, message) = switch ((domain, isFreeProvider)) {
      (null, _) => (
          Icons.info_outline_rounded,
          colors.textLight,
          'Use an address at your organisation’s own domain if you have one — '
              'it is how the verified badge is earned.',
        ),
      (final d?, true) => (
          Icons.warning_amber_rounded,
          colors.warning,
          '$d is a public mail provider, so this account cannot earn a '
              'verified badge. You can still set everything up and change '
              'the address later.',
        ),
      (final d?, false) => (
          Icons.verified_outlined,
          colors.success,
          'You will be able to verify $d and earn the badge students look '
              'for.',
        ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: colour),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: text.bodySmall?.copyWith(height: 1.4)),
        ),
      ],
    );
  }
}
