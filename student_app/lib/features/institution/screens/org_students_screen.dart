import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/empty_state.dart';
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
                      color: colors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome_rounded,
                        color: colors.accent, size: 20),
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
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _selectedProgramId,
                        decoration: InputDecoration(
                          labelText: 'Program',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All programs', overflow: TextOverflow.ellipsis),
                          ),
                          ..._programs.map(
                            (p) => DropdownMenuItem<String?>(
                              value: p['id'] as String,
                              child: Text(p['name'] as String? ?? 'Program',
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedProgramId = val);
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _minScore,
                          items: const [
                            DropdownMenuItem(value: 40, child: Text('40%+ fit')),
                            DropdownMenuItem(value: 60, child: Text('60%+ fit')),
                            DropdownMenuItem(value: 80, child: Text('80%+ fit')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _minScore = val);
                              _load();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : candidates.isEmpty
                        ? EmptyState(
                            icon: Icons.auto_awesome_outlined,
                            title: 'No matches found',
                            message: _minScore > 40
                                ? 'Try lowering the minimum match score to see more candidates.'
                                : 'As students complete their Education Passports and match your intake criteria, they will appear here.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                              itemCount: candidates.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 14),
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

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Score Badge & Title
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: scoreColor),
                      const SizedBox(width: 4),
                      Text(
                        '${card.score}% match',
                        style: text.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.isShared && card.sharedName != null
                            ? card.sharedName!
                            : 'Candidate · ${card.token.length > 8 ? card.token.substring(0, 8) : card.token}',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        card.programName,
                        style: text.bodySmall?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (card.isShared)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.successLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Passport shared',
                      style: text.labelSmall?.copyWith(color: colors.success, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // Profile Attributes Chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (card.currentCountry != null)
                  _Pill(
                    icon: Icons.public_rounded,
                    label: AppConstants.homeCountries[card.currentCountry] ?? card.currentCountry!,
                  ),
                if (card.targetLevels.isNotEmpty)
                  _Pill(
                    icon: Icons.school_outlined,
                    label: card.targetLevels.map((l) => AppConstants.studyLevels[l] ?? l).join(', '),
                  ),
                if (card.gradeBand != null)
                  _Pill(icon: Icons.grade_outlined, label: 'Grades: ${card.gradeBand}'),
                if (card.budgetBand != null)
                  _Pill(icon: Icons.payments_outlined, label: card.budgetBand!),
                if (card.intendedIntake != null)
                  _Pill(icon: Icons.calendar_today_outlined, label: card.intendedIntake!),
                if (card.englishBand != null)
                  _Pill(icon: Icons.translate_rounded, label: 'English: ${card.englishBand}'),
              ],
            ),

            if (card.reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MATCH REASONS',
                      style: text.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.reasons.join(' · '),
                      style: text.bodySmall?.copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                if (!card.alreadyActioned) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isBusy ? null : onInvite,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Invite to apply'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Expanded(
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 16, color: colors.success),
                          const SizedBox(width: 6),
                          Text(
                            'Invited',
                            style: text.labelMedium?.copyWith(
                              color: colors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (!card.isShared)
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : onRequestAccess,
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('Request passport'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: text.labelSmall?.copyWith(color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
