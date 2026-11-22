import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../applications/providers/applications_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../messages/providers/messages_provider.dart';
import '../../passport/providers/passport_provider.dart';
import '../models/program.dart';
import '../providers/discover_provider.dart';

/// A program in full, with how the student measures against its requirements.
class ProgramScreen extends StatefulWidget {
  final String programId;

  const ProgramScreen({super.key, required this.programId});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  Program? _program;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<DiscoverProvider>();
    final program = await provider.fetchProgram(widget.programId);
    if (!mounted) return;
    setState(() {
      _program = program;
      _loading = false;
      _error = program == null
          ? provider.error ?? 'That program could not be found.'
          : null;
    });
  }

  /// While the draft is being created, so the button cannot be tapped twice.
  bool _starting = false;

  Future<void> _apply() async {
    final program = _program;
    if (program == null) return;

    final intake = program.intakes.isEmpty
        ? null
        : await showModalBottomSheet<String>(
            context: context,
            useRootNavigator: true,
            builder: (sheet) => _IntakeSheet(intakes: program.intakes),
          );

    // Picking no intake from a sheet that offered some is a "not now".
    if (!mounted || (program.intakes.isNotEmpty && intake == null)) return;

    // Says plainly what submitting will do, since it grants the institution
    // access to the passport. A student should never discover that afterwards.
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheet) => _StartSheet(
        programme: program.name,
        institution: program.institution?.name ?? 'the institution',
        intake: intake,
      ),
    );

    if (confirmed != true || !mounted) return;

    final applications = context.read<ApplicationsProvider>();
    setState(() => _starting = true);
    final id = await applications.start(
      institutionId: program.institutionId,
      programId: program.id,
      intake: intake,
    );

    if (!mounted) return;
    setState(() => _starting = false);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            applications.error ?? 'Could not start an application.',
          ),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }
    context.push('${AppConstants.routeApplicationDetail}/$id');
  }

  Future<void> _message() async {
    final program = _program;
    if (program == null) return;

    final messages = context.read<MessagesProvider>();
    final conversationId = await messages.openConversation(
      institutionId: program.institutionId,
      subject: 'About ${program.name}',
    );

    if (!mounted) return;
    if (conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messages.error ?? 'Could not start a conversation.'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }
    context.push('${AppConstants.routeChat}/$conversationId');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final program = _program;
    final passport = context.watch<PassportProvider>().passport;
    final discover = context.watch<DiscoverProvider>();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (program == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: _error ?? 'Not found', onRetry: _load),
      );
    }

    final institution = program.institution;
    final isSaved = discover.isSaved(program.id);
    // Staff open their own programmes from the page preview. Saving, applying,
    // asking and booking are a student's actions, so they are left out.
    final isStudent = context.watch<AuthProvider>().user?.isStudent ?? true;

    // How the student actually measures up. Shown even when they fall short,
    // because a student deserves to know before spending an application on it.
    final meetsGrade =
        passport?.normalizedGrade != null &&
        program.normalizedMinGrade != null &&
        passport!.normalizedGrade! >= program.normalizedMinGrade!;
    final meetsEnglish =
        passport?.englishBand != null &&
        program.minEnglishBand != null &&
        passport!.englishBand! >= program.minEnglishBand!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Program'),
        actions: [
          if (isStudent)
            IconButton(
              tooltip: isSaved ? 'Saved' : 'Save',
              onPressed: () => discover.toggleSaved(program.id),
              icon: Icon(
                isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: isSaved ? colors.accent : null,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(program.name, style: text.headlineMedium),
          const SizedBox(height: 12),
          if (institution != null)
            InkWell(
              onTap: () => context.push(
                '${AppConstants.routeInstitution}/${institution.id}',
              ),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    InstitutionAvatar(
                      logoUrl: institution.logoUrl,
                      initials: institution.initials,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(institution.name, style: text.titleMedium),
                          Text(institution.location, style: text.bodySmall),
                        ],
                      ),
                    ),
                    if (institution.isVerified)
                      VerifiedBadge(
                        subject: VerifiedSubject.institution,
                        compact: true,
                      ),
                    Icon(Icons.chevron_right_rounded, color: colors.textLight),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Fact(icon: Icons.school_outlined, label: program.levelLabel),
              _Fact(
                icon: Icons.schedule_rounded,
                label: program.durationDisplay,
              ),
              if (program.scholarshipAvailable)
                _Fact(
                  icon: Icons.savings_rounded,
                  label: 'Scholarships',
                  highlight: true,
                ),
            ],
          ),

          const SizedBox(height: 24),
          _Section(
            title: 'Cost',
            rows: [
              ('Tuition', program.tuitionDisplay),
              if (program.intakes.isNotEmpty)
                ('Intakes', program.intakes.join(', ')),
            ],
          ),

          const SizedBox(height: 16),
          Text('Entry requirements', style: text.titleLarge),
          const SizedBox(height: 12),
          _RequirementRow(
            label: 'Grades',
            requirement: program.entryRequirementDisplay,
            // Only claims a verdict when both sides are known; an unstated
            // requirement is shown as unknown rather than guessed at.
            status: program.normalizedMinGrade == null
                ? _ReqStatus.unknown
                : passport?.normalizedGrade == null
                ? _ReqStatus.needsInfo
                : meetsGrade
                ? _ReqStatus.met
                : _ReqStatus.notMet,
            yourValue: passport?.gradeDisplay,
          ),
          const SizedBox(height: 10),
          _RequirementRow(
            label: 'English',
            requirement: program.englishRequirementDisplay,
            status: program.minEnglishBand == null
                ? _ReqStatus.unknown
                : passport?.englishBand == null
                ? _ReqStatus.needsInfo
                : meetsEnglish
                ? _ReqStatus.met
                : _ReqStatus.notMet,
            yourValue: passport?.englishBand == null
                ? null
                : 'IELTS ${passport!.englishBand!.toStringAsFixed(1)} equivalent',
          ),

          if (program.requirements.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Also required', style: text.titleLarge),
            const SizedBox(height: 10),
            ...program.requirements.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 5, color: colors.textLight),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${entry.key}: ${entry.value}',
                        style: text.bodyMedium?.copyWith(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),
          if (!isStudent)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This is how students see this programme. They can apply, '
                      'ask a question or book a meeting from here.',
                      style: text.bodySmall?.copyWith(
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            PillButton(
              label: 'Start an application',
              icon: Icons.arrow_forward_rounded,
              primary: true,
              busy: _starting,
              height: 54,
              onTap: _apply,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Ask a question',
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: _message,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    label: 'Meet me',
                    icon: Icons.event_available_outlined,
                    onTap: () => context.push(
                      '${AppConstants.routeAppointmentRequest}'
                      '?institution=${program.institutionId}'
                      '&program=${program.id}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _Fact({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = highlight ? colors.warning : colors.textSecondary;
    final bg = highlight ? colors.warningLight : colors.surfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleLarge),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(rows[i].$1, style: text.bodySmall),
                      ),
                      Expanded(
                        child: Text(
                          rows[i].$2,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < rows.length - 1)
                  Divider(
                    height: 1,
                    color: colors.divider,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

enum _ReqStatus { met, notMet, unknown, needsInfo }

class _RequirementRow extends StatelessWidget {
  final String label;
  final String requirement;
  final _ReqStatus status;
  final String? yourValue;

  const _RequirementRow({
    required this.label,
    required this.requirement,
    required this.status,
    this.yourValue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final (icon, color, note) = switch (status) {
      _ReqStatus.met => (
        Icons.check_circle_rounded,
        colors.success,
        'You meet this',
      ),
      _ReqStatus.notMet => (
        Icons.info_rounded,
        colors.warning,
        'Below the stated minimum — you can still apply',
      ),
      _ReqStatus.needsInfo => (
        Icons.help_outline_rounded,
        colors.textLight,
        'Add this to your passport to compare',
      ),
      _ReqStatus.unknown => (
        Icons.remove_circle_outline_rounded,
        colors.textLight,
        'Not published by the institution',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.titleSmall),
                Text(requirement, style: text.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  yourValue == null ? note : '$note · yours: $yourValue',
                  style: text.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

/// "Which intake?" — one row per intake, a calendar mark, a chevron.
class _IntakeSheet extends StatelessWidget {
  final List<String> intakes;
  const _IntakeSheet({required this.intakes});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              'Which intake?',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'When you would like to start.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          for (final intake in intakes)
            Pressable.surface(
              onTap: () => Navigator.of(context).pop(intake),
              semanticLabel: intake,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.calendar_month_outlined,
                        size: 20,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        intake,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: colors.textLight),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// The confirmation before a draft is created. A sheet rather than an alert:
/// the two facts a student must know are set out as points, and the answer is
/// a full-width button under the thumb.
class _StartSheet extends StatelessWidget {
  final String programme;
  final String institution;
  final String? intake;

  const _StartSheet({
    required this.programme,
    required this.institution,
    this.intake,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    Widget point(IconData icon, String title, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: colors.textPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: text.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit_document,
                  size: 28,
                  color: colors.background,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Start your application',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                [
                  programme,
                  institution,
                  if (intake != null) intake!,
                ].join(' · '),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            point(
              Icons.drafts_outlined,
              'It starts as a draft',
              'Nothing is sent yet. Attach documents and review it before you '
                  'submit.',
            ),
            point(
              Icons.lock_open_outlined,
              'Submitting shares your passport',
              '$institution will be able to see your Education Passport. You '
                  'can take that back at any time.',
            ),
            const SizedBox(height: 8),
            PillButton(
              label: 'Create draft',
              primary: true,
              height: 54,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
