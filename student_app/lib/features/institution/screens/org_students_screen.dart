import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../widgets/org_ui.dart';
import '../models/matched_student.dart';
import '../providers/institution_provider.dart';

/// Reverse admission: browsing students whose academic profile matches the institution's programs.
///
/// Students here are pseudonymous until they choose to share their passport.
/// Admissions officers can invite them to apply or request passport access.
class OrgStudentsScreen extends StatefulWidget {
  const OrgStudentsScreen({super.key});

  @override
  State<OrgStudentsScreen> createState() => _OrgStudentsScreenState();
}

class _OrgStudentsScreenState extends State<OrgStudentsScreen> {
  final _service = SupabaseService.instance;

  bool _loading = true;
  String? _error;
  List<MatchedStudentCard> _cards = [];
  List<Map<String, dynamic>> _programs = [];

  String? _selectedProgramId;
  int _minScore = 40;
  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final institutionId = context.read<InstitutionProvider>().institutionId;
    if (institutionId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final progRes = await _service.client
          .from('programs')
          .select('id, name, level')
          .eq('institution_id', institutionId)
          .eq('is_active', true)
          .order('name');

      var query = _service.client
          .from('matched_student_cards')
          .select()
          .eq('institution_id', institutionId)
          .gte('score', _minScore);

      if (_selectedProgramId != null && _selectedProgramId!.isNotEmpty) {
        query = query.eq('program_id', _selectedProgramId!);
      }

      final cardsRes = await query.order('score', ascending: false).limit(150);

      if (!mounted) return;
      setState(() {
        _programs = (progRes as List).cast<Map<String, dynamic>>();
        _cards = (cardsRes as List)
            .map((r) => MatchedStudentCard.fromMap((r as Map).cast<String, dynamic>()))
            .toList();
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

  /// Deduplicate by token to show unique candidates with their best match score.
  List<MatchedStudentCard> get _groupedCandidates {
    final map = <String, MatchedStudentCard>{};
    for (final card in _cards) {
      final existing = map[card.token];
      if (existing == null || card.score > existing.score) {
        map[card.token] = card;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  Future<void> _inviteStudent(MatchedStudentCard card) async {
    final noteController = TextEditingController(
      text: 'We reviewed your academic qualifications and would be delighted to welcome your application to ${card.programName}.',
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = ctx.colors;
        final text = Theme.of(ctx).textTheme;

        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mail_outline_rounded,
                        color: colors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Invite candidate to apply', style: text.titleMedium),
                        Text(
                          'For ${card.programName}',
                          style: text.bodySmall?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'The student remains anonymous until they accept and share their passport. They will receive this invitation directly in their portal.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: noteController,
                label: 'Personal note to the candidate',
                hint: 'Include details on why they stand out or available funding...',
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Send invite'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busyAction = true);
    try {
      await _service.client.rpc('institution_invite_student', params: {
        'p_token': card.token,
        'p_program_id': card.programId,
        'p_note': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation sent to candidate.'),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _requestAccess(MatchedStudentCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Passport access?'),
        content: const Text(
          'This asks the student to share their full Education Passport (name, transcripts, test scores and documents) with your institution.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Request access'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busyAction = true);
    try {
      await _service.client.rpc('institution_request_access', params: {
        'p_token': card.token,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access requested. You will be notified when they accept.'),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final candidates = _groupedCandidates;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Matched students'),
      ),
      body: Column(
        children: [
          // Two rows of pills rather than two dropdown fields: every option is
          // visible, and changing one is a single tap rather than three.
          const SizedBox(height: 4),
          OrgFilterBar<String?>(
            selected: _selectedProgramId,
            onSelected: (v) {
              setState(() => _selectedProgramId = v);
              _load();
            },
            options: [
              (null, 'All programmes'),
              for (final p in _programs)
                (p['id'] as String, p['name'] as String? ?? 'Programme'),
            ],
          ),
          const SizedBox(height: 8),
          OrgFilterBar<int>(
            selected: _minScore,
            onSelected: (v) {
              setState(() => _minScore = v);
              _load();
            },
            options: const [
              (40, 'Any fit'),
              (60, '60% fit or more'),
              (80, '80% fit or more'),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.divider),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : candidates.isEmpty
                        ? EmptyState(
                            icon: Icons.person_search_outlined,
                            title: 'No matches found',
                            message: _minScore > 40
                                ? 'Try lowering the minimum match score to see more candidates.'
                                : 'As students complete their Education Passports and match your intake criteria, they will appear here.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                              itemCount: candidates.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final card = candidates[index];
                                return _CandidateCard(
                                  card: card,
                                  onInvite: () => _inviteStudent(card),
                                  onRequestAccess: () => _requestAccess(card),
                                  isBusy: _busyAction,
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final MatchedStudentCard card;
  final VoidCallback onInvite;
  final VoidCallback onRequestAccess;
  final bool isBusy;

  const _CandidateCard({
    required this.card,
    required this.onInvite,
    required this.onRequestAccess,
    required this.isBusy,
  });

  Color _scoreColor(BuildContext context, int score) {
    final colors = context.colors;
    if (score >= 80) return colors.success;
    if (score >= 60) return colors.accent;
    return colors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final scoreColor = _scoreColor(context, card.score);
    final token = card.token.length >= 6
        ? card.token.substring(0, 6).toUpperCase()
        : card.token.toUpperCase();
    final name = card.isShared && card.sharedName != null
        ? card.sharedName!
        : 'Student $token';
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final facts = <String>[
      if (card.currentCountry != null) countryLabel(card.currentCountry),
      if (card.targetLevels.isNotEmpty)
        card.targetLevels
            .map((l) => AppConstants.studyLevels[l] ?? l)
            .join(', '),
      if (card.gradeBand != null) 'Grades ${card.gradeBand}',
      if (card.englishBand != null) 'English ${card.englishBand}',
      if (card.budgetBand != null) card.budgetBand!,
      if (card.intendedIntake != null) card.intendedIntake!,
    ];

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
          Row(
            children: [
              StudentMark(
                isShared: card.isShared,
                initials: initials.isEmpty ? '?' : initials,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(card.programName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: colors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The fit as a ring: the one number on the card that is a
              // judgement, so it is the one place colour is used.
              SizedBox.square(
                dimension: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (card.score / 100).clamp(0.0, 1.0),
                        strokeWidth: 3.5,
                        backgroundColor: colors.surfaceVariant,
                        color: scoreColor,
                      ),
                    ),
                    Text('${card.score}%',
                        style: text.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final f in facts) OrgTag(f)],
            ),
          ],
          if (card.reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Why they match',
                style: text.labelMedium?.copyWith(color: colors.textSecondary)),
            const SizedBox(height: 4),
            for (final reason in card.reasons.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_rounded,
                          size: 15, color: colors.success),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(reason,
                          style: text.bodySmall?.copyWith(height: 1.35)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: card.alreadyActioned
                    ? OrgPillButton(
                        label: 'Invited',
                        icon: Icons.check_rounded,
                        tone: colors.success,
                      )
                    : OrgPillButton(
                        label: 'Invite to apply',
                        primary: true,
                        onTap: isBusy ? null : onInvite,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: card.isShared
                    ? OrgPillButton(
                        label: 'View passport',
                        onTap: () => context.push(
                            '${AppConstants.routeOrgStudent}/${card.token}'),
                      )
                    : OrgPillButton(
                        label: 'Request passport',
                        onTap: isBusy ? null : onRequestAccess,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


