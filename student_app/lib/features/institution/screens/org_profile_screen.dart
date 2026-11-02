import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/profile_photo_sheet.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../passport/providers/passport_provider.dart';
import '../providers/institution_provider.dart';
import '../widgets/section_editor.dart';

/// The institution's public page, edited from the app.
///
/// Everything here is what a student is weighing up — cost of living, whether
/// their own qualifications clear the bar, when applications close, whether
/// there is funding. Laid out as a list of sections rather than one long form,
/// because on a phone a twenty-field form is unusable and staff fill this in
/// over several sittings.
class OrgProfileScreen extends StatefulWidget {
  const OrgProfileScreen({super.key});

  @override
  State<OrgProfileScreen> createState() => _OrgProfileScreenState();
}

class _OrgProfileScreenState extends State<OrgProfileScreen> {
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PassportProvider>().load();
    });
  }

  Future<void> _pickAndUploadLogo() async {
    final provider = context.read<InstitutionProvider>();
    final managed = provider.managed;
    if (managed == null) return;

    final hasExisting = managed.institution.logoUrl != null &&
        managed.institution.logoUrl!.isNotEmpty;

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
            backgroundColor: context.colors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<InstitutionProvider>();
    final managed = provider.managed;

    if (managed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = managed.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our page'),
        actions: [
          IconButton(
            tooltip: 'Preview public page',
            icon: const Icon(Icons.remove_red_eye_outlined),
            onPressed: () {
              context.push(
                '${AppConstants.routeInstitution}/${managed.institution.id}',
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (managed.completeness / 100).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: colors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(
              managed.completeness >= 70 ? colors.success : colors.warning,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // University profile header with logo and details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                InstitutionAvatar(
                  logoUrl: managed.institution.logoUrl,
                  initials: managed.institution.initials,
                  size: 64,
                  onEdit: _pickAndUploadLogo,
                  isBusy: _uploadingLogo,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        managed.institution.name,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        managed.institution.location,
                        style: text.bodySmall?.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickAndUploadLogo,
                        child: Text(
                          managed.institution.logoUrl == null
                              ? 'Upload university logo'
                              : 'Change university logo',
                          style: text.labelSmall?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(
                  '${managed.completeness}%',
                  style: text.displaySmall?.copyWith(
                    color: managed.completeness >= 70
                        ? colors.success
                        : colors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    managed.completeness >= 70
                        ? 'Your page answers what students ask. Keep intakes '
                            'and deadlines current.'
                        : 'Students skip pages that do not answer cost, entry '
                            'requirements and deadlines.',
                    style: text.bodySmall?.copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push(AppConstants.routeOrgFollowers),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.surfaceVariant),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.people_alt_outlined, color: colors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${provider.demand.followers} student follower${provider.demand.followers == 1 ? '' : 's'}',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Following your posts and university updates',
                          style: text.bodySmall?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.textSecondary),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),
          Text('About', style: text.titleLarge),
          const SizedBox(height: 12),

          _TextSection(
            title: 'Tagline',
            subtitle: 'One line, shown under your name.',
            value: profile.tagline,
            hint: 'Where ambition meets opportunity',
            onSave: (v) => provider.saveProfile({'tagline': v}),
          ),
          _TextSection(
            title: 'About',
            subtitle: 'What this place is.',
            value: profile.about,
            maxLines: 6,
            onSave: (v) => provider.saveProfile({'about': v}),
          ),
          _TextSection(
            title: 'Campus life',
            subtitle: 'Clubs, sport, the city, what a week looks like.',
            value: profile.campusLife,
            maxLines: 5,
            onSave: (v) => provider.saveProfile({'campus_life': v}),
          ),
          _TextSection(
            title: 'Accommodation',
            subtitle: 'Where a student lives in first year — one of the two '
                'questions every parent asks.',
            value: profile.accommodation,
            maxLines: 5,
            onSave: (v) => provider.saveProfile({'accommodation': v}),
          ),

          const SizedBox(height: 22),
          Text('Numbers', style: text.titleLarge),
          const SizedBox(height: 12),

          _NumbersSection(provider: provider),

          const SizedBox(height: 22),
          Text('Sections', style: text.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Each of these appears as its own block on your page.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),

          SectionEditor(
            icon: Icons.calendar_month_rounded,
            title: 'Intakes',
            subtitle: 'When applications open and close.',
            table: 'institution_intakes',
            summarise: (row) => row['label'] as String? ?? '—',
            detail: (row) => _dateRange(row),
            fields: const [
              SectionField(key: 'label', label: 'Label', hint: 'Fall 2026',
                  required: true),
              SectionField(key: 'applications_open', label: 'Applications open',
                  type: SectionFieldType.date),
              SectionField(key: 'applications_close', label: 'Applications close',
                  type: SectionFieldType.date),
              SectionField(key: 'term_starts', label: 'Term starts',
                  type: SectionFieldType.date),
            ],
          ),

          SectionEditor(
            icon: Icons.checklist_rounded,
            title: 'Entry requirements',
            subtitle: 'Set a general rule, then override it per country. '
                'Students see the one that applies to them.',
            table: 'institution_entry_requirements',
            summarise: (row) =>
                AppConstants.homeCountries[row['from_country']] ??
                row['from_country'] as String? ??
                'Anywhere',
            detail: (row) => row['qualification'] as String? ?? 'No detail yet',
            fields: [
              SectionField(
                key: 'from_country',
                label: 'Students from',
                type: SectionFieldType.choice,
                options: AppConstants.homeCountries,
                emptyLabel: 'Anywhere',
              ),
              SectionField(
                key: 'level',
                label: 'Study level',
                type: SectionFieldType.choice,
                options: AppConstants.studyLevels,
                emptyLabel: 'Any level',
              ),
              const SectionField(
                key: 'qualification',
                label: 'Qualification',
                hint: 'WASSCE with five credits including English',
              ),
              const SectionField(
                key: 'min_grade_value',
                label: 'Minimum grade',
                type: SectionFieldType.number,
              ),
              SectionField(
                key: 'min_grade_scheme',
                label: 'Grading scheme',
                type: SectionFieldType.choice,
                options: AppConstants.gradingSchemes,
                emptyLabel: 'Not specified',
              ),
              const SectionField(
                key: 'min_english_band',
                label: 'English (IELTS or equivalent)',
                type: SectionFieldType.number,
              ),
              const SectionField(
                key: 'note',
                label: 'Anything else',
                type: SectionFieldType.multiline,
              ),
            ],
          ),

          SectionEditor(
            icon: Icons.savings_rounded,
            title: 'Scholarships',
            subtitle: 'Funding often decides whether a matched student can '
                'actually come.',
            table: 'institution_scholarships',
            summarise: (row) => row['name'] as String? ?? '—',
            detail: (row) => row['coverage'] as String? ?? 'Varies',
            fields: const [
              SectionField(key: 'name', label: 'Name', required: true),
              SectionField(key: 'coverage', label: 'What it covers',
                  hint: '50% of tuition'),
              SectionField(key: 'amount', label: 'Amount',
                  type: SectionFieldType.currency, hint: '5,000'),
              SectionField(key: 'criteria', label: 'Who qualifies',
                  type: SectionFieldType.multiline),
              SectionField(key: 'deadline', label: 'Deadline',
                  type: SectionFieldType.date),
              SectionField(key: 'url', label: 'Link'),
            ],
          ),

          SectionEditor(
            icon: Icons.contact_mail_rounded,
            title: 'Contacts',
            subtitle: 'Who a student should reach, and for what.',
            table: 'institution_contacts',
            summarise: (row) => row['role'] as String? ?? '—',
            detail: (row) =>
                row['email'] as String? ?? row['name'] as String? ?? '',
            fields: const [
              SectionField(key: 'role', label: 'Role', required: true,
                  hint: 'International admissions'),
              SectionField(key: 'name', label: 'Name'),
              SectionField(key: 'email', label: 'Email',
                  type: SectionFieldType.email),
              SectionField(key: 'phone', label: 'Phone'),
            ],
          ),

          SectionEditor(
            icon: Icons.help_outline_rounded,
            title: 'Questions students ask',
            subtitle: 'Answer the common ones once instead of in every message.',
            table: 'institution_faqs',
            summarise: (row) => row['question'] as String? ?? '—',
            detail: (row) => row['answer'] as String? ?? '',
            fields: const [
              SectionField(key: 'question', label: 'Question', required: true),
              SectionField(key: 'answer', label: 'Answer',
                  type: SectionFieldType.multiline, required: true),
            ],
          ),
        ],
      ),
    );
  }

  static String _dateRange(Map<String, dynamic> row) {
    final close = row['applications_close'] as String?;
    final starts = row['term_starts'] as String?;
    if (close == null && starts == null) return 'No dates yet';
    final parts = <String>[];
    if (close != null) parts.add('closes $close');
    if (starts != null) parts.add('starts $starts');
    return parts.join(' · ');
  }
}

// ── A single editable text field, saved on its own ──────────────────────────

class _TextSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? value;
  final String? hint;
  final int maxLines;
  final Future<bool> Function(String?) onSave;

  const _TextSection({
    required this.title,
    this.subtitle,
    this.value,
    this.hint,
    this.maxLines = 1,
    required this.onSave,
  });

  @override
  State<_TextSection> createState() => _TextSectionState();
}

class _TextSectionState extends State<_TextSection> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final value = _controller.text.trim();
    final ok = await widget.onSave(value.isEmpty ? null : value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = !ok;
    });

    if (!ok) {
      final error = context.read<InstitutionProvider>().error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Could not save.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomTextField(
              controller: _controller,
              label: widget.title,
              hint: widget.hint,
              maxLines: widget.maxLines,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (!_dirty) setState(() => _dirty = true);
              },
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(height: 1.4),
              ),
            ],
            // The save button only appears once something changed, so the page
            // is a readable summary until you actually edit it.
            if (_dirty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.colors.onAccent),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Costs and sizes, saved together ─────────────────────────────────────────

class _NumbersSection extends StatefulWidget {
  final InstitutionProvider provider;

  const _NumbersSection({required this.provider});

  @override
  State<_NumbersSection> createState() => _NumbersSectionState();
}

class _NumbersSectionState extends State<_NumbersSection> {
  late final _livingMin = TextEditingController(
      text: formatAmountWithCommas(widget.provider.profile?.costOfLivingMin));
  late final _livingMax = TextEditingController(
      text: formatAmountWithCommas(widget.provider.profile?.costOfLivingMax));
  late final _applicationFee = TextEditingController(
      text: formatAmountWithCommas(widget.provider.profile?.applicationFee));
  late final _students = TextEditingController(
      text: formatAmountWithCommas(widget.provider.profile?.studentCount));
  late final _founded = TextEditingController(
      text: widget.provider.profile?.foundedYear?.toString() ?? '');

  late String _currency = widget.provider.profile?.costCurrency ?? 'USD';
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _livingMin, _livingMax, _applicationFee, _students, _founded,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _num(TextEditingController c) =>
      c.text.trim().isEmpty ? null : num.tryParse(c.text.trim().replaceAll(',', ''));

  Future<void> _save() async {
    setState(() => _saving = true);

    final ok = await widget.provider.saveProfile({
      'cost_of_living_min': _num(_livingMin),
      'cost_of_living_max': _num(_livingMax),
      'cost_currency': _currency,
      'fee_currency': _currency,
      'application_fee': _num(_applicationFee),
      'student_count': _num(_students)?.toInt(),
      'founded_year': _num(_founded)?.toInt(),
    });

    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = !ok;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.provider.error ?? 'Could not save.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    void touched() {
      if (!_dirty) setState(() => _dirty = true);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: const ['USD', 'GBP', 'EUR', 'CAD', 'AUD']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              setState(() => _currency = v ?? 'USD');
              touched();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _livingMin,
                  label: 'Living costs from',
                  hint: '12,000',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  onChanged: (_) => touched(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: _livingMax,
                  label: 'to',
                  hint: '18,000',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  onChanged: (_) => touched(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // Says where tuition lives, so nobody enters it twice.
            'Living costs only — tuition belongs to each program.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _applicationFee,
            label: 'Application fee',
            hint: '120',
            keyboardType: TextInputType.number,
            inputFormatters: const [ThousandsSeparatorInputFormatter()],
            onChanged: (_) => touched(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _students,
                  label: 'Students',
                  hint: '41,000',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  onChanged: (_) => touched(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: _founded,
                  label: 'Founded',
                  hint: '1964',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => touched(),
                ),
              ),
            ],
          ),
          if (_dirty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.onAccent),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
