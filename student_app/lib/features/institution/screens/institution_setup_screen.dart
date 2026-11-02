import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/step_header.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/institution_provider.dart';

/// Step two of institution sign-up: the listing itself.
///
/// Also reached on its own, outside sign-up, whenever staff sign in with no
/// institution yet — there is nothing to show a dashboard about, and the rest
/// of the shell needs an institution id to query anything. That is why this is
/// driven by `needsSetup` rather than by navigation from step one: a sign-up
/// interrupted here resumes here on the next sign-in.
///
/// [kind] comes from step one when it is part of sign-up, and is null when
/// someone arrives cold; the dropdown is shown either way so it stays
/// correctable.
class InstitutionSetupScreen extends StatefulWidget {
  final String? kind;

  const InstitutionSetupScreen({super.key, this.kind});

  @override
  State<InstitutionSetupScreen> createState() => _InstitutionSetupScreenState();
}

class _InstitutionSetupScreenState extends State<InstitutionSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _website = TextEditingController();
  final _domain = TextEditingController();
  final _description = TextEditingController();
  String? _country;
  late String _kind = widget.kind ?? 'university';

  static const _kindKey = 'pending_institution_kind';

  @override
  void initState() {
    super.initState();

    // Step one remembers the kind, because email confirmation can separate the
    // two steps and the query parameter does not survive that.
    if (widget.kind == null) {
      SharedPreferences.getInstance().then((prefs) {
        final remembered = prefs.getString(_kindKey);
        if (remembered != null &&
            AppConstants.institutionKinds.containsKey(remembered) &&
            mounted) {
          setState(() => _kind = remembered);
        }
      }).catchError((_) {/* the dropdown still works */});
    }

    // The work email from step one is the domain they are about to verify, so
    // typing it a second time is pure friction — and a mismatch between the
    // two is the single most common reason verification fails.
    final email = context.read<AuthProvider>().email ?? '';
    final parts = email.trim().toLowerCase().split('@');
    if (parts.length == 2 && parts[1].contains('.')) {
      _domain.text = parts[1];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _website.dispose();
    _domain.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final provider = context.read<InstitutionProvider>();
    final ok = await provider.createInstitution(
      name: _name.text,
      country: _country!,
      kind: _kind,
      city: _city.text,
      website: _website.text,
      emailDomain: _domain.text,
      description: _description.text,
    );

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not create your listing.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
    if (ok) {
      // Consumed: a later listing under the same account is impossible, and a
      // stale value would preselect the wrong kind if this screen is reopened.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kindKey);
      } catch (_) {/* harmless */}
    }
    // On success the shell rebuilds onto the dashboard: the provider now has
    // an institution, so `needsSetup` is false.
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<InstitutionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your institution'),
        actions: [
          TextButton(
            onPressed: () => context.read<AuthProvider>().signOut(),
            child: const Text('Sign out'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: colors.accentGradient,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(Icons.apartment_rounded,
                            color: context.colors.onAccent, size: 28),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const StepHeader(step: 2, label: 'Your listing'),
                    const SizedBox(height: 16),
                    Text('Create your listing', style: text.displaySmall),
                    const SizedBox(height: 8),
                    Text(
                      'This is what students see. You can fill in the rest — '
                      'photos, costs, entry requirements — straight after.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: const InputDecoration(
                        labelText: 'Organisation type',
                        prefixIcon: Icon(Icons.category_outlined, size: 20),
                      ),
                      items: AppConstants.institutionKinds.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _kind = v ?? 'university'),
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _name,
                      label: _kind == 'embassy'
                          ? 'Mission name'
                          : 'Institution name',
                      hint: _kind == 'embassy'
                          ? 'High Commission of Canada'
                          : 'Maplecrest University',
                      prefixIcon: Icons.apartment_outlined,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Enter the full name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _country,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        prefixIcon: Icon(Icons.public_rounded, size: 20),
                      ),
                      items: AppConstants.popularDestinations.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setState(() => _country = v),
                      validator: (v) => v == null ? 'Choose a country' : null,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _city,
                      label: 'City',
                      hint: 'Toronto',
                      prefixIcon: Icons.location_city_outlined,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _website,
                      label: 'Website',
                      hint: 'https://maplecrest.ca',
                      prefixIcon: Icons.link_rounded,
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _domain,
                      label: 'Email domain',
                      // The basis of the verified badge, so it has to be bare —
                      // a CHECK constraint rejects a scheme or a path.
                      hint: 'maplecrest.ca — no https:// or path',
                      prefixIcon: Icons.alternate_email_rounded,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _description,
                      label: 'About',
                      hint: 'A few sentences students will read.',
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 26),
                    ElevatedButton(
                      onPressed: provider.saving ? null : _submit,
                      child: provider.saving
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: context.colors.onAccent,
                              ),
                            )
                          : const Text('Create listing'),
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
