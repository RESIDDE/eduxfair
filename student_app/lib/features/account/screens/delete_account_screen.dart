import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../auth/providers/auth_provider.dart';

/// Deleting an account, and saying what that means before it happens.
///
/// App Review guideline 5.1.1(v) requires this to be startable inside the app
/// and to remove the account record rather than deactivate it. Apple's
/// reference page also rules out sending people to email support, so there is
/// no "contact us to delete" path here.
///
/// The screen is deliberately slow to get through — a list of what goes, a
/// typed confirmation, and the password — because this is irreversible and
/// the passport behind it took hours to fill in. It is still two taps from
/// Settings, which is what "easy to find" means.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _phrase = 'DELETE';

  /// For staff: what leaving does to each institution they belong to. Null
  /// until loaded, and never loaded for students.
  List<Map<String, dynamic>>? _impact;

  @override
  void initState() {
    super.initState();
    // The button enables itself as the phrase is typed.
    _confirm.addListener(_rebuild);
    if (context.read<AuthProvider>().user?.isStaff ?? false) _loadImpact();
  }

  Future<void> _loadImpact() async {
    try {
      final rows = await SupabaseService.instance.client.rpc('my_deletion_impact');
      if (!mounted) return;
      setState(() => _impact = [
            for (final r in (rows as List? ?? const []))
              (r as Map).cast<String, dynamic>(),
          ]);
    } catch (_) {
      // The screen still works without it; the general copy below covers it.
      if (mounted) setState(() => _impact = const []);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _confirm.removeListener(_rebuild);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _ready =>
      _confirm.text.trim().toUpperCase() == _phrase &&
      _password.text.isNotEmpty;

  Future<void> _delete() async {
    final auth = context.read<AuthProvider>();
    // AppUser does not carry the address; the auth session does.
    final email = SupabaseService.instance.client.auth.currentUser?.email;
    if (email == null) {
      setState(() => _error = 'You are not signed in.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final client = SupabaseService.instance.client;

    try {
      // Re-authenticate first. A phone left unlocked on a table should not be
      // enough to erase someone's passport, and the session alone proves only
      // that it was signed in at some point.
      await client.auth.signInWithPassword(email: email, password: _password.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message.toLowerCase().contains('credential')
            ? 'That password is not right.'
            : e.message;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = SupabaseService.describeError(e);
      });
      return;
    }

    try {
      final res = await client.functions.invoke(
        'delete-account',
        body: {'confirm': _phrase},
      );
      final data = res.data;
      final ok = data is Map && data['deleted'] == true;
      if (!ok) {
        final message = data is Map && data['error'] is String
            ? data['error'] as String
            : 'The account could not be deleted. Nothing has been removed.';
        throw Exception(message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = SupabaseService.describeError(e);
      });
      return;
    }

    // The account is gone; the local session is now meaningless.
    await auth.signOut();
    if (!mounted) return;
    context.go(AppConstants.routeLogin);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your account has been deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final isStaff = context.watch<AuthProvider>().user?.isStaff ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'This cannot be undone.',
            style: text.headlineSmall?.copyWith(color: colors.error),
          ),
          const SizedBox(height: 14),
          Text('Deleting your account removes:', style: text.bodyLarge),
          const SizedBox(height: 10),
          for (final line in isStaff
              ? const [
                  'Your profile, name and photo',
                  'Posts you wrote, including ones published for your '
                      'institution',
                  'Messages you wrote in your institution’s conversations',
                  'Your place on your institution’s team',
                ]
              : const [
                  'Your Education Passport, including every document you '
                      'uploaded',
                  'Your profile, handle, bio and photo',
                  'Your posts, comments, likes and saved items',
                  'Your messages, and your place in any conversation',
                  'Every institution’s access to you',
                  'Your applications and meeting history',
                ])
            _Bullet(line, colors.error),
          // What happens to the institution is the part staff most need to
          // know, and it differs per institution — so it is spelled out for
          // each one rather than left to a generic bullet.
          if (isStaff && _impact == null) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          for (final inst in _impact ?? const <Map<String, dynamic>>[]) ...[
            const SizedBox(height: 16),
            _InstitutionImpact(inst),
          ],
          const SizedBox(height: 18),
          Text('What stays:', style: text.bodyLarge),
          const SizedBox(height: 10),
          // Guideline 5.1.1(v): if anything is retained, say which.
          _Bullet(
            'Records we have to keep by law, such as accounting records',
            colors.textLight,
          ),
          _Bullet(
            'Any safety report you filed about someone else — the report '
            'stays, with your name removed from it, so that deleting an '
            'account cannot be used to withdraw it',
            colors.textLight,
          ),
          const SizedBox(height: 22),
          Divider(color: colors.divider),
          const SizedBox(height: 18),
          Text(
            'Type $_phrase to confirm',
            style: text.titleMedium,
          ),
          const SizedBox(height: 10),
          CustomTextField(
            controller: _confirm,
            label: '',
            hint: _phrase,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _password,
            label: 'Your password',
            hint: 'Confirm it is you',
            obscureText: true,
            prefixIcon: Icons.lock_outline_rounded,
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: text.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          ],
          const SizedBox(height: 22),
          CustomButton(
            label: 'Delete my account',
            isLoading: _busy,
            onPressed: _ready && !_busy ? _delete : null,
            backgroundColor: colors.error,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => context.pop(),
              child: const Text('Keep my account'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One institution, and what deleting this account does to it.
class _InstitutionImpact extends StatelessWidget {
  final Map<String, dynamic> impact;
  const _InstitutionImpact(this.impact);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final name = impact['name'] as String? ?? 'Your institution';
    final removes = impact['removes_institution'] == true;
    final others = (impact['other_members'] as num?)?.toInt() ?? 0;
    final apps = (impact['applications'] as num?)?.toInt() ?? 0;
    final convs = (impact['conversations'] as num?)?.toInt() ?? 0;
    final handsOver = impact['hands_over_ownership'] == true;

    String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: removes ? colors.errorLight : colors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                removes ? Icons.warning_amber_rounded : Icons.apartment_rounded,
                size: 18,
                color: removes ? colors.error : colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  removes ? '$name will be deleted too' : '$name stays',
                  style: text.titleSmall?.copyWith(
                      color: removes ? colors.error : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            removes
                ? 'You are its only team member, so its page, programmes, '
                    'posts and prospectus are removed with you — along with '
                    '${plural(apps, 'application', 'applications')} and '
                    '${plural(convs, 'conversation', 'conversations')} with '
                    'students. To keep it, add a colleague from More → Team '
                    'before you delete your account.'
                : '${plural(others, 'colleague', 'colleagues')} ${others == 1 ? 'keeps' : 'keep'} running '
                    'it, and its page, applications and conversations are '
                    'unaffected.'
                    '${handsOver ? ' You are its only owner, so ownership passes to the longest-serving colleague.' : ''}',
            style: text.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final Color tint;

  const _Bullet(this.text, this.tint);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 10),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      );
}
