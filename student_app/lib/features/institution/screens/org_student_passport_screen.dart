import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/document_viewer.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../models/pipeline.dart';
import '../models/shared_student.dart';
import '../providers/org_desk_provider.dart';

/// A student, as far as they have let this institution see them.
///
/// Reached from the pipeline, the inbox and the matched-students list, all of
/// which know the student only by match token. With a live passport share this
/// is everything: who they are, how to reach them, the whole passport and
/// every document in it. Without one it is the applications they made here and
/// the documents they chose to send — and it says why there is not more.
class OrgStudentPassportScreen extends StatefulWidget {
  final String token;

  const OrgStudentPassportScreen({super.key, required this.token});

  @override
  State<OrgStudentPassportScreen> createState() =>
      _OrgStudentPassportScreenState();
}

class _OrgStudentPassportScreenState extends State<OrgStudentPassportScreen> {
  SharedStudent? _student;
  String? _error;
  bool _loading = true;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final student =
          await context.read<OrgDeskProvider>().studentPassport(widget.token);
      if (!mounted) return;
      setState(() {
        _student = student;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseService.describeError(e);
        _loading = false;
      });
    }
  }

  /// In the app, not in a browser. Storage policy is still the gate: the
  /// viewer reads the file with this officer's own session.
  Future<void> _open(SharedDocument doc) => openDocument(
        context,
        bucket: AppConstants.bucketPassportDocs,
        path: doc.storagePath,
        fileName: doc.fileName,
        mime: doc.mime,
        title: AppConstants.documentKinds[doc.kind] ?? doc.kind,
      );

  @override
  Widget build(BuildContext context) {
    final student = _student;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(student?.displayName ?? 'Student'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    children: [
                      _Header(student: student!),
                      const SizedBox(height: 16),
                      if (!student.isShared) ...[
                        const _NotSharedNotice(),
                        const SizedBox(height: 16),
                      ],
                      if (student.isShared) ...[
                        _PassportSection(student: student),
                        const SizedBox(height: 16),
                      ],
                      _DocumentsSection(
                        student: student,
                        opening: _opening,
                        onOpen: _open,
                      ),
                      if (student.applications.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _ApplicationsSection(student: student),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────────

String _country(String? code) =>
    AppConstants.homeCountries[code] ??
    AppConstants.popularDestinations[code] ??
    code ??
    '—';

String _date(DateTime? d) {
  if (d == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// 32000 -> 32,000. Numeric columns arrive as numbers or strings.
String _money(Object? value) {
  final n = num.tryParse('${value ?? 0}')?.round() ?? 0;
  return n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

String _size(int? bytes) {
  final n = bytes ?? 0;
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _Card extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;

  const _Card({this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(title!,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final SharedStudent student;
  const _Header({required this.student});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (student.isShared)
                UserAvatar(
                  avatarUrl: student.avatarUrl,
                  initials: student.initials,
                  size: 60,
                )
              else
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      color: colors.textSecondary),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.displayName,
                        style: text.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (student.handle != null)
                      Text('@${student.handle}',
                          style: text.bodyMedium
                              ?.copyWith(color: colors.textLight)),
                    const SizedBox(height: 6),
                    _Tag(
                      icon: student.isShared
                          ? Icons.verified_user_outlined
                          : Icons.lock_outline_rounded,
                      label: student.isShared
                          ? 'Passport shared ${_date(student.sharedAt)}'
                          : 'Passport not shared',
                      tone: student.isShared ? colors.success : colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (student.isShared &&
              (student.email != null || student.phone != null || student.country != null)) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: 6),
            if (student.email != null)
              _ContactRow(
                icon: Icons.mail_outline_rounded,
                value: student.email!,
                onTap: () => launchUrl(Uri.parse('mailto:${student.email}')),
              ),
            if (student.phone != null)
              _ContactRow(
                icon: Icons.phone_outlined,
                value: student.phone!,
                onTap: () => launchUrl(Uri.parse('tel:${student.phone}')),
              ),
            if (student.country != null)
              _ContactRow(
                icon: Icons.public_rounded,
                value: 'Applying from ${_country(student.country)}',
              ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  const _ContactRow({required this.icon, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: onTap != null ? colors.accent : colors.textPrimary,
                      fontWeight: onTap != null ? FontWeight.w600 : null,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  const _Tag({required this.icon, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 5),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _NotSharedNotice extends StatelessWidget {
  const _NotSharedNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'This student has not shared their passport with you, so their name, '
        'contact details and passport stay private. Below are the documents '
        'they chose to send you. Ask for access from Matched students, or '
        'request a document on their application.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
      ),
    );
  }
}

class _PassportSection extends StatelessWidget {
  final SharedStudent student;
  const _PassportSection({required this.student});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final p = student.passport;

    if (p == null) {
      return const _Card(
        title: 'Education Passport',
        child: Text('They shared access but have not filled in a passport yet.'),
      );
    }

    final completeness = (p['completeness'] as num?)?.toInt() ?? 0;
    final verified = p['verification_status'] == 'verified';
    String? str(String key) {
      final v = p[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    List<String> list(String key) =>
        (p[key] as List? ?? const []).map((e) => e.toString()).toList();

    final english = str('english_test_name');
    final rows = <(String, String?)>[
      ('Nationality', str('nationality') == null ? null : _country(str('nationality'))),
      ('Lives in', str('current_country') == null ? null : _country(str('current_country'))),
      ('Date of birth', str('date_of_birth') == null ? null : _date(DateTime.tryParse(str('date_of_birth')!))),
      ('Highest qualification', str('highest_qualification')),
      ('Grade', str('grade_value') == null
          ? null
          : '${str('grade_value')} · ${AppConstants.gradingSchemes[str('grade_scheme')] ?? str('grade_scheme') ?? ''}'),
      ('English', english == null || english == 'none'
          ? null
          : '${AppConstants.englishTests[english] ?? english.toUpperCase()} ${str('english_score') ?? ''}'),
      ('Budget', str('budget_max') == null
          ? null
          : '${str('budget_currency') ?? 'USD'} ${_money(p['budget_min'])} – ${_money(p['budget_max'])}'),
      ('Intended intake', str('intended_intake')),
    ];

    final targets = <(String, List<String>)>[
      ('Countries', list('target_countries').map(_country).toList()),
      ('Levels', list('target_levels').map((l) => AppConstants.studyLevels[l] ?? l).toList()),
      ('Fields', list('target_fields').map((f) => student.fieldLabels[f] ?? f).toList()),
    ];

    return _Card(
      title: 'Education Passport',
      trailing: _Tag(
        icon: verified ? Icons.verified_rounded : Icons.hourglass_empty_rounded,
        label: verified ? 'Verified' : 'Not verified',
        tone: verified ? colors.success : colors.textSecondary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: completeness / 100,
                    minHeight: 6,
                    backgroundColor: colors.surfaceVariant,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$completeness% complete', style: text.labelMedium),
            ],
          ),
          const SizedBox(height: 14),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(label,
                        style: text.bodySmall?.copyWith(color: colors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(value ?? '—',
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: value == null ? colors.textLight : null)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          for (final (label, values) in targets)
            if (values.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wants to study · $label',
                        style: text.bodySmall?.copyWith(color: colors.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final v in values)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(v, style: text.labelMedium),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          if (str('bio') != null) ...[
            const SizedBox(height: 14),
            Text('About them',
                style: text.bodySmall?.copyWith(color: colors.textSecondary)),
            const SizedBox(height: 4),
            Text(str('bio')!, style: text.bodyMedium?.copyWith(height: 1.45)),
          ],
        ],
      ),
    );
  }
}

class _DocumentsSection extends StatelessWidget {
  final SharedStudent student;
  final String? opening;
  final void Function(SharedDocument) onOpen;

  const _DocumentsSection({
    required this.student,
    required this.opening,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final sentHere = {
      for (final a in student.applications) ...a.documentIds,
    };

    return _Card(
      title: 'Documents (${student.documents.length})',
      child: student.documents.isEmpty
          ? Text(
              student.isShared
                  ? 'They have not uploaded any documents yet.'
                  : 'They have not sent you any documents yet.',
              style: text.bodySmall,
            )
          : Column(
              children: [
                for (final doc in student.documents)
                  InkWell(
                    onTap: opening == null ? () => onOpen(doc) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              (doc.mime ?? '').startsWith('image/')
                                  ? Icons.image_outlined
                                  : Icons.description_outlined,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppConstants.documentKinds[doc.kind] ?? doc.kind,
                                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${doc.fileName} · ${_size(doc.sizeBytes)} · ${_date(doc.createdAt)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(color: colors.textLight),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    if (doc.verificationStatus == 'verified')
                                      _Tag(icon: Icons.verified_rounded, label: 'Verified', tone: colors.success),
                                    if (sentHere.contains(doc.id))
                                      _Tag(icon: Icons.send_rounded, label: 'Sent to you', tone: colors.accent),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          opening == doc.id
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.open_in_new_rounded,
                                  size: 20, color: colors.textSecondary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ApplicationsSection extends StatelessWidget {
  final SharedStudent student;
  const _ApplicationsSection({required this.student});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return _Card(
      title: 'Their applications to you',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final app in student.applications) ...[
            Text(app.programName ?? 'General application',
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              [
                stageLabel(app.stage),
                if (app.intake != null) app.intake!,
                if (app.submittedAt != null) 'applied ${_date(app.submittedAt)}',
              ].join(' · '),
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            for (final r in app.requests)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      r.isOutstanding
                          ? Icons.schedule_rounded
                          : Icons.check_circle_rounded,
                      size: 16,
                      color: r.isOutstanding ? colors.warning : colors.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${AppConstants.documentKinds[r.kind] ?? r.kind} — '
                        '${r.isOutstanding ? 'waiting for the student' : 'sent ${_date(r.fulfilledAt)}'}',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (app != student.applications.last) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}
