import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/pressable.dart';
import '../../auth/providers/auth_provider.dart';

/// Changing your name, as a sheet that rises with the keyboard.
///
/// Save is a word, not a filled button: the header reads Cancel · Edit name ·
/// Save, the way every iOS edit sheet does, and Save only lights up once there
/// is something worth saving. Tapping it saves and closes in one motion — no
/// second confirmation, no dialog left behind.
Future<void> showEditNameSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      // Above the shell, so the nav bar cannot sit on top of it.
      useRootNavigator: true,
      // Lets the sheet ride up with the keyboard instead of being covered.
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => const _EditNameSheet(),
    );

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet();

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final String _original;
  late final TextEditingController _name;
  final _focus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _original = context.read<AuthProvider>().user?.fullName ?? '';
    _name = TextEditingController(text: _original)
      ..addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _value => _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool get _canSave =>
      !_saving &&
      _value != _original.trim() &&
      AppValidators.validateName(_value) == null;

  Future<void> _save() async {
    final problem = AppValidators.validateName(_value);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (!_canSave) return;

    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateProfile(fullName: _value);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = auth.error ?? 'Could not save your name. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grabber — drawn here because the header sits tight beneath it.
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Cancel · Edit name · Save
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'Edit name',
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _HeaderAction(
                      label: 'Cancel',
                      color: colors.textSecondary,
                      onTap: _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _saving
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 22),
                            child: SizedBox.square(
                              dimension: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _HeaderAction(
                            label: 'Save',
                            bold: true,
                            color: _canSave
                                ? colors.textPrimary
                                : colors.textLight,
                            haptic: HapticKind.impact,
                            onTap: _canSave ? _save : null,
                          ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _error != null
                        ? colors.error
                        : (_focus.hasFocus
                            ? colors.textSecondary.withValues(alpha: 0.5)
                            : Colors.transparent),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Full name',
                            style: text.labelSmall?.copyWith(
                              color: colors.textLight,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Focus(
                            onFocusChange: (_) => setState(() {}),
                            child: TextField(
                              controller: _name,
                              focusNode: _focus,
                              autofocus: true,
                              enabled: !_saving,
                              maxLength: 60,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.name],
                              onSubmitted: (_) => _save(),
                              style: text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                              cursorColor: colors.textPrimary,
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                counterText: '',
                                contentPadding:
                                    EdgeInsets.only(top: 4, bottom: 2),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_name.text.isNotEmpty && !_saving)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: _name.clear,
                        icon: Icon(Icons.cancel_rounded,
                            size: 20, color: colors.textLight),
                      ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Text(
                  _error ??
                      'Use the name on your documents. Institutions see it '
                          'on your Education Passport.',
                  key: ValueKey(_error),
                  style: text.bodySmall?.copyWith(
                    height: 1.4,
                    color: _error != null ? colors.error : colors.textLight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A word in the sheet's header that behaves like a button.
class _HeaderAction extends StatelessWidget {
  final String label;
  final Color color;
  final bool bold;
  final HapticKind haptic;
  final VoidCallback? onTap;

  const _HeaderAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.bold = false,
    this.haptic = HapticKind.selection,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: haptic,
      semanticLabel: label,
      child: Padding(
        // 44pt tall at the least, whatever the word's width.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
          child: Text(label),
        ),
      ),
    );
  }
}
