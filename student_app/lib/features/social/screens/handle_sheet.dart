import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../passport/providers/passport_provider.dart';

/// Changing the public handle, and the bio that sits under it.
///
/// Every student is now issued one at signup by `derive_student_handle()`, so
/// this is a rename rather than a first claim — it exists because the handle is
/// the one public part of a student's identity, and being handed a name is not
/// the same as being stuck with it.
///
/// It is still reached as a claim by anyone whose account predates that, and by
/// the reply and reshare paths as a fallback.
///
/// The bio is here rather than in the passport editor because it is the same
/// kind of thing as the handle — public, chosen, visible to anyone who opens
/// the profile. `passports.bio` is a different column with a different
/// audience: institutions, and only after a share.
Future<bool> openClaimHandleSheet(BuildContext context) async {
  final claimed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ClaimHandleSheet(),
  );
  return claimed == true;
}

class _ClaimHandleSheet extends StatefulWidget {
  const _ClaimHandleSheet();

  @override
  State<_ClaimHandleSheet> createState() => _ClaimHandleSheetState();
}

class _ClaimHandleSheetState extends State<_ClaimHandleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _handle = TextEditingController();
  final _bio = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The one they were issued, so a rename starts from what people already
    // know them by rather than from a blank field.
    final passport = context.read<PassportProvider>();
    _bio.text = passport.bio ?? '';
    final current = passport.handle;
    if (current != null) {
      _handle.text = current;
    } else {
      final first = context.read<AuthProvider>().user?.firstName ?? '';
      final seed = first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (seed.length >= 3) _handle.text = seed;
    }
  }

  @override
  void dispose() {
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// Mirrors the regex inside `claim_handle()`, so the common mistakes are
  /// caught before a round trip. Uniqueness is still the server's to decide.
  String? _validate(String? v) {
    final value = (v ?? '').trim().toLowerCase();
    if (value.isEmpty) return 'Choose a handle';
    if (!RegExp(r'^[a-z][a-z0-9_]{2,19}$').hasMatch(value)) {
      return '3 to 20 characters: letters, numbers and underscores, '
          'starting with a letter';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final passport = context.read<PassportProvider>();
    final name = context.read<AuthProvider>().user?.fullName ?? '';
    var ok = await passport.claimHandle(
      _handle.text.trim().toLowerCase(),
      name,
    );

    // The handle first, deliberately: set_social_bio needs a social_profiles
    // row to exist, and for a first-time claim this is the call that makes one.
    if (ok) {
      final bio = _bio.text.trim();
      ok = await passport.saveBio(bio.isEmpty ? null : bio);
    }

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(passport.error ?? 'Could not save your profile.'),
        backgroundColor: context.colors.error,
      ),
    );
    passport.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final saving = context.watch<PassportProvider>().saving;

    // Scrollable, and capped at most of the screen. The bio field plus its
    // counter and helper made this taller than the space a bottom sheet is
    // given, and a Column that overflows does not scroll — it just clips,
    // which put the save button under the edge of the screen with no way to
    // reach it.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.read<PassportProvider>().handle == null
                      ? 'Choose your handle'
                      : 'Your public profile',
                  style: text.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'This is the name other people see when you post or reply. It '
                  'is the only public part of your account — your passport stays '
                  'private until you share it, and your full name is never part '
                  'of your handle unless you put it there.',
                  style: text.bodySmall?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _handle,
                  autofocus: true,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    prefixText: '@',
                    labelText: 'Handle',
                    hintText: 'amara_o',
                  ),
                  validator: _validate,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bio,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 280,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText:
                        'Studying for a masters in public health. '
                        'Looking at Canada and Ireland for 2027.',
                    helperText:
                        'Shown on your profile. Leave it empty to remove it.',
                    helperMaxLines: 2,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colors.onAccent,
                          ),
                        )
                      : const Text('Save profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
