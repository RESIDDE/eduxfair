import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/utils/profile_photo_sheet.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/surface.dart';
import '../../../core/widgets/verified_badge.dart';
import '../providers/institution_provider.dart';

/// Your listing, and the domain check that earns the verified badge.
///
/// Ported from the React console's InstitutionSettingsPage, which institutions
/// no longer have access to. Same two jobs in the same order, because the order
/// matters: the badge is the thing people come here for, and it needs a domain
/// set in the form below before it can do anything.
class OrgSettingsScreen extends StatelessWidget {
  const OrgSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final institutions = context.watch<InstitutionProvider>();
    final institution = institutions.institution;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Listing and verification'),
      ),
      body: institution == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: const [
                _DomainVerification(),
                SizedBox(height: 16),
                _ListingForm(),
              ],
            ),
    );
  }
}

/// The two ways to earn the verified badge.
///
/// **Ask for review** — inserts a row into `verifications`, which an admin then
/// resolves. The schema was built for this: "students and institutions can
/// *request* verification but never award it to themselves", and the insert
/// policy allows the subject while only admin may update the status. No email
/// is involved, which matters because a new listing usually has not set up mail
/// on its own domain yet.
///
/// **Verify by email** — the `verify-institution-domain` Edge Function sends a
/// six-digit code to an address on the institution's own domain and checks it.
/// The code is stored hashed in a table with no RLS policies at all, so staff
/// cannot read their own code and skip the email. Stronger evidence, but it
/// needs working mail on that domain.
///
/// Review is offered first because it always works. Neither path can set the
/// badge directly: `guard_self_verification` raises on any status change by the
/// subject.
class _DomainVerification extends StatefulWidget {
  const _DomainVerification();

  @override
  State<_DomainVerification> createState() => _DomainVerificationState();
}

class _DomainVerificationState extends State<_DomainVerification> {
  final _service = SupabaseService.instance;
  final _email = TextEditingController();
  final _code = TextEditingController();

  bool _awaitingCode = false;
  bool _byEmail = false;
  bool _busy = false;
  bool _loadingRequest = true;
  String? _error;
  String? _notice;

  /// The institution's most recent verification request, if any.
  Map<String, dynamic>? _request;

  String? get _requestStatus => _request?['status'] as String?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRequest());
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  /// `verifications_select_subject` lets staff read their own institution's
  /// requests, which is how this card knows whether one is already waiting.
  Future<void> _loadRequest() async {
    final id = context.read<InstitutionProvider>().institutionId;
    if (id == null) return;
    try {
      final rows = await _service.client
          .from('verifications')
          .select()
          .eq('subject_type', 'institution')
          .eq('subject_id', id)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted) return;
      setState(() {
        _request = rows.isEmpty ? null : rows.first;
        _loadingRequest = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRequest = false);
    }
  }

  /// Asks for review. Status defaults to 'pending' and only an admin may move
  /// it, so this cannot award anything — it just joins the queue.
  Future<void> _requestReview(String institutionId) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _service.client.from('verifications').insert({
        'subject_type': 'institution',
        'subject_id': institutionId,
        'evidence': {
          'method': 'review_request',
          'requested_at': DateTime.now().toUtc().toIso8601String(),
        },
      });
      await _loadRequest();
      if (mounted) {
        setState(() => _notice =
            'Sent. Eduxfair will review your listing and the badge appears here '
            'once it is approved.');
      }
    } catch (e) {
      // verifications_one_open allows one pending row per subject, so a second
      // tap lands here rather than queueing twice.
      if (mounted) setState(() => _error = SupabaseService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode(String institutionId) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _service.invoke('verify-institution-domain',
          body: {'institution_id': institutionId, 'email': _email.text.trim()});

      // The function returns 200 with an `error` string when it cannot send —
      // the dev server does exactly that, since it has no mail.
      if (result['error'] != null) {
        setState(() => _error = result['error'] as String);
        return;
      }
      setState(() {
        _awaitingCode = true;
        _notice = result['sent'] == true
            ? 'Code sent to ${_email.text.trim()}. It expires in '
                '${result['expires_in_minutes']} minutes.'
            : 'The code was created but the email could not be sent. '
                'Contact Eduxfair support.';
      });
    } catch (e) {
      setState(() => _error = SupabaseService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCode(String institutionId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.invoke('verify-institution-domain',
          body: {'institution_id': institutionId, 'code': _code.text.trim()});

      if (result['error'] != null) {
        setState(() => _error = result['error'] as String);
        return;
      }
      if (!mounted) return;
      setState(() {
        _awaitingCode = false;
        _notice = 'Verified. Your badge is now showing to students.';
        _code.clear();
      });
      // The badge lives on the institution row, so reload rather than patch it
      // locally — apply_verification_decision() may have moved other fields.
      await context.read<InstitutionProvider>().refresh();
    } catch (e) {
      setState(() => _error = SupabaseService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final text = Theme.of(context).textTheme;
    final institution = context.watch<InstitutionProvider>().institution!;
    final hasDomain = (institution.emailDomain ?? '').isNotEmpty;

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.successLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.verified_user_rounded,
                    color: colors.success, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Domain verification', style: text.titleMedium),
              ),
              if (institution.isVerified)
                const VerifiedBadge(
                  subject: VerifiedSubject.institution,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A party controlling an address on this institution\'s own domain '
            'confirmed the listing. It is not a claim about accreditation.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary, height: 1.45),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            _Banner(message: _error!, tone: _BannerTone.error),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 14),
            _Banner(message: _notice!, tone: _BannerTone.success),
          ],

          const SizedBox(height: 16),

          if (institution.isVerified)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: colors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Verified on ${institution.emailDomain ?? 'your domain'}',
                    style: text.bodySmall?.copyWith(color: colors.success),
                  ),
                ),
              ],
            )
          else if (_loadingRequest)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (_requestStatus == 'pending')
            Row(
              children: [
                Icon(Icons.hourglass_top_rounded, size: 16, color: colors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Waiting for review. Eduxfair will look at your listing and '
                    'the badge appears here once approved.',
                    style: text.bodySmall
                        ?.copyWith(color: colors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            )
          else if (!_byEmail) ...[
            // Review first, because it always works. The email route needs
            // working mail on the institution's own domain, which a new
            // listing usually has not set up yet.
            if (_requestStatus == 'rejected') ...[
              _Banner(
                 message: (_request?['review_note'] as String?) ??
                    'That request was not approved. Check your listing details '
                    'below and ask again.',
                tone: _BannerTone.error,
              ),
              const SizedBox(height: 14),
            ],
            CustomButton(
              label: _requestStatus == 'rejected'
                  ? 'Ask for review again'
                  : 'Ask Eduxfair to verify us',
              isLoading: _busy,
              onPressed: () => _requestReview(institution.id),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _byEmail = true),
              child: const Text('Verify by email on our domain instead'),
            ),
          ]
          else if (_awaitingCode) ...[
            CustomTextField(
              controller: _code,
              label: '6-digit code',
              hint: '123456',
              keyboardType: TextInputType.number,
              inputFormatters: [LengthLimitingTextInputFormatter(6)],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    label: 'Verify',
                    isLoading: _busy,
                    onPressed: () => _confirmCode(institution.id),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _awaitingCode = false;
                            _notice = null;
                          }),
                  child: const Text('Start over'),
                ),
              ],
            ),
          ] else ...[
            CustomTextField(
              controller: _email,
              label: 'An email address on your domain',
              hint: hasDomain
                  ? 'admissions@${institution.emailDomain}'
                  : 'Add your domain below first',
              keyboardType: TextInputType.emailAddress,
              readOnly: !hasDomain,
            ),
            const SizedBox(height: 6),
            Text(
              hasDomain
                  ? 'Must be @${institution.emailDomain}'
                  : 'Set your email domain in the form below, then come back.',
              style: text.bodySmall?.copyWith(color: colors.textLight),
            ),
            const SizedBox(height: 12),
            CustomButton(
              label: 'Send code',
              isLoading: _busy,
              onPressed: hasDomain ? () => _sendCode(institution.id) : null,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _byEmail = false;
                        _error = null;
                        _notice = null;
                      }),
              child: const Text('Ask Eduxfair to verify us instead'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListingForm extends StatefulWidget {
  const _ListingForm();

  @override
  State<_ListingForm> createState() => _ListingFormState();
}

class _ListingFormState extends State<_ListingForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _website;
  late final TextEditingController _domain;
  late final TextEditingController _description;
  String? _country;
  bool _saved = false;
  bool _uploadingLogo = false;

  Future<void> _uploadLogo() async {
    final provider = context.read<InstitutionProvider>();
    final institution = provider.institution;
    if (institution == null) return;

    final hasExisting =
        institution.logoUrl != null && institution.logoUrl!.isNotEmpty;
    final res = await showProfilePhotoPickerSheet(
      context: context,
      title: 'University logo / profile picture',
      hasExisting: hasExisting,
    );

    if (res == null || !mounted) return;

    setState(() => _uploadingLogo = true);
    try {
      if (res.isRemoved) {
        final ok = await provider.removeLogo();
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('University logo removed.')),
          );
        }
      } else if (res.bytes != null && res.fileName != null) {
        final ok = await provider.uploadLogo(
          bytes: res.bytes!,
          fileName: res.fileName!,
          mimeType: res.mimeType,
        );
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('University logo updated.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SupabaseService.describeError(e)),
            backgroundColor: Theme.of(context).extension<AppThemeColors>()!.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final institution = context.read<InstitutionProvider>().institution!;
    _name = TextEditingController(text: institution.name);
    _city = TextEditingController(text: institution.city ?? '');
    _website = TextEditingController(text: institution.website ?? '');
    _domain = TextEditingController(text: institution.emailDomain ?? '');
    _description = TextEditingController(text: institution.description ?? '');
    _country = institution.country.isEmpty ? null : institution.country;
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

  /// The CHECK constraint requires a bare domain, so a pasted URL is cleaned
  /// here rather than bounced back as `institutions_email_domain_is_bare`.
  String? _bareDomain() {
    final raw = _domain.text.trim().toLowerCase();
    if (raw.isEmpty) return null;
    return raw.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/.*$'), '');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saved = false);

    final ok = await context.read<InstitutionProvider>().saveInstitution({
      'name': _name.text.trim(),
      'country': _country,
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
      'email_domain': _bareDomain(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
    });

    if (!mounted) return;
    if (ok) {
      // Reflect the cleaned domain back, so the field shows what was stored.
      _domain.text = _bareDomain() ?? '';
      setState(() => _saved = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final text = Theme.of(context).textTheme;
    final institutions = context.watch<InstitutionProvider>();

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your listing', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'This is what students see.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),

            if (institutions.error != null) ...[
              const SizedBox(height: 14),
              _Banner(message: institutions.error!, tone: _BannerTone.error),
            ],
            if (_saved) ...[
              const SizedBox(height: 14),
              const _Banner(message: 'Saved.', tone: _BannerTone.success),
            ],

            const SizedBox(height: 18),
            if (institutions.institution != null) ...[
              Row(
                children: [
                  InstitutionAvatar(
                    logoUrl: institutions.institution!.logoUrl,
                    initials: institutions.institution!.initials,
                    size: 60,
                    onEdit: _uploadLogo,
                    isBusy: _uploadingLogo,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'University logo',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Shown across student discover, posts, and chats.',
                          style: text.bodySmall?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _uploadingLogo ? null : _uploadLogo,
                          icon: const Icon(Icons.photo_camera_outlined, size: 16),
                          label: Text(
                            institutions.institution!.logoUrl == null
                                ? 'Upload logo'
                                : 'Change logo',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
            ],

            CustomTextField(
              controller: _name,
              label: 'Institution name',
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
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _country = v),
              validator: (v) => v == null ? 'Choose a country' : null,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _city,
              label: 'City',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _website,
              label: 'Website',
              hint: 'https://your-institution.edu',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _domain,
              label: 'Email domain',
              hint: 'maplecrest.ca',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 6),
            Text(
              'Bare domain only — no https:// or path. This is where the '
              'verification code is sent.',
              style: text.bodySmall?.copyWith(color: colors.textLight),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _description,
              label: 'About',
              maxLines: 5,
            ),
            const SizedBox(height: 20),
            CustomButton(
              label: 'Save changes',
              isLoading: institutions.saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerTone { success, error }

class _Banner extends StatelessWidget {
  final String message;
  final _BannerTone tone;

  const _Banner({required this.message, required this.tone});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final isError = tone == _BannerTone.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? colors.errorLight : colors.successLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isError ? colors.error : colors.success,
              height: 1.4,
            ),
      ),
    );
  }
}
