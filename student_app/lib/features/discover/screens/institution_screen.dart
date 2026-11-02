import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../messages/providers/messages_provider.dart';
import '../models/prospectus.dart';
import '../providers/discover_provider.dart';
import 'discover_screen.dart' show ProgramTile;

/// The institution prospectus.
///
/// What a student is actually deciding on: what it costs to live there, whether
/// their own qualifications clear the bar, when applications close, whether
/// there is funding. The whole page arrives in one call, with entry
/// requirements already narrowed to this student's country.
class InstitutionScreen extends StatefulWidget {
  final String institutionId;

  const InstitutionScreen({super.key, required this.institutionId});

  @override
  State<InstitutionScreen> createState() => _InstitutionScreenState();
}

class _InstitutionScreenState extends State<InstitutionScreen> {
  Prospectus? _prospectus;
  bool _loading = true;
  String? _error;
  bool _isFollowing = false;
  int _followerCount = 0;
  bool _busyFollow = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<DiscoverProvider>();
    final prospectus = await provider.fetchProspectus(widget.institutionId);

    bool isFollowing = false;
    int followerCount = prospectus?.institution.followerCount ?? 0;

    try {
      final followStatus = await SupabaseService.instance.client.rpc(
        'get_institution_follow_status',
        params: {'p_institution_id': widget.institutionId},
      );
      if (followStatus != null && followStatus is Map) {
        isFollowing = followStatus['is_following'] as bool? ?? false;
        followerCount = (followStatus['follower_count'] as num?)?.toInt() ?? followerCount;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _prospectus = prospectus;
      _isFollowing = isFollowing;
      _followerCount = followerCount;
      _loading = false;
      _error = prospectus == null
          ? provider.error ?? 'That institution could not be found.'
          : null;
    });
  }

  Future<void> _toggleFollow() async {
    final institution = _prospectus?.institution;
    if (institution == null || _busyFollow) return;

    setState(() => _busyFollow = true);
    try {
      final res = await SupabaseService.instance.client.rpc(
        'follow_institution',
        params: {
          'p_institution_id': institution.id,
          'p_follow': !_isFollowing,
        },
      );
      if (res != null && res is Map) {
        setState(() {
          _isFollowing = res['is_following'] as bool? ?? !_isFollowing;
          _followerCount =
              (res['follower_count'] as num?)?.toInt() ?? _followerCount;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: context.colors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  Future<void> _message() async {
    final institution = _prospectus?.institution;
    if (institution == null) return;

    final messages = context.read<MessagesProvider>();
    final conversationId = await messages.openConversation(
      institutionId: institution.id,
      subject: 'Enquiry about ${institution.name}',
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final prospectus = _prospectus;
    if (prospectus == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: _error ?? 'Not found', onRetry: _load),
      );
    }

    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final institution = prospectus.institution;
    final profile = prospectus.profile;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _HeaderSliver(prospectus: prospectus),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    InstitutionAvatar(
                      logoUrl: institution.logoUrl,
                      initials: institution.initials,
                      size: 60,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(institution.name, style: text.headlineSmall),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14, color: colors.textLight),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(institution.location,
                                    style: text.bodySmall),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (profile.tagline != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    profile.tagline!,
                    style: text.titleMedium?.copyWith(color: colors.accent),
                  ),
                ],

                const SizedBox(height: 12),
                Row(
                  children: [
                    VerificationStatusChip(
                      status: institution.verificationStatus,
                      subject: VerifiedSubject.institution,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_alt_outlined, size: 14, color: colors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '$_followerCount ${_followerCount == 1 ? 'follower' : 'followers'}',
                            style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── What this student needs ────────────────────────────────
                // Highest on the page after the name, because it is the thing
                // that decides whether the rest is worth reading.
                if (prospectus.requirementForMe != null) ...[
                  const SizedBox(height: 22),
                  _RequirementCard(
                    requirement: prospectus.requirementForMe!,
                    country: prospectus.resolvedForCountry,
                  ),
                ],

                if (prospectus.openIntakes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _IntakeStrip(intakes: prospectus.openIntakes),
                ],

                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busyFollow ? null : _toggleFollow,
                        icon: _busyFollow
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _isFollowing
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 18,
                                color: _isFollowing ? colors.success : colors.primary,
                              ),
                        label: Text(_isFollowing ? 'Following' : 'Follow'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          foregroundColor: _isFollowing ? colors.success : colors.primary,
                          side: BorderSide(
                            color: _isFollowing
                                ? colors.success.withValues(alpha: 0.5)
                                : colors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _message,
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: const Text('Message'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context.push(
                          '${AppConstants.routeAppointmentRequest}'
                          '?institution=${institution.id}',
                        ),
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: const Text('Meet me'),
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 48)),
                      ),
                    ),
                  ],
                ),

                // ── Facts ──────────────────────────────────────────────────
                if (_facts(prospectus).isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _FactGrid(facts: _facts(prospectus)),
                ],

                _Section(title: 'About', body: profile.about),
                _Section(title: 'Campus life', body: profile.campusLife),
                _Section(title: 'Accommodation', body: profile.accommodation),

                if (profile.rankings.isNotEmpty ||
                    profile.accreditation.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text('Recognition', style: text.titleLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...profile.rankings.map(
                        (r) => _Pill(label: r.display, icon: Icons.trending_up_rounded),
                      ),
                      ...profile.accreditation.map(
                        (a) => _Pill(label: a, icon: Icons.verified_outlined),
                      ),
                    ],
                  ),
                ],

                if (prospectus.scholarships.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('Scholarships', style: text.titleLarge),
                  const SizedBox(height: 12),
                  ...prospectus.scholarships.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ScholarshipCard(scholarship: s),
                    ),
                  ),
                ],

                if (prospectus.programs.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('Programs (${prospectus.programs.length})',
                      style: text.titleLarge),
                  const SizedBox(height: 12),
                  ...prospectus.programs.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ProgramTile(program: p),
                    ),
                  ),
                ],

                if (profile.applicationSteps.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('How to apply', style: text.titleLarge),
                  const SizedBox(height: 12),
                  ...profile.applicationSteps.asMap().entries.map(
                        (e) => _Step(index: e.key + 1, step: e.value),
                      ),
                ],

                if (prospectus.faqs.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('Questions students ask', style: text.titleLarge),
                  const SizedBox(height: 8),
                  ...prospectus.faqs.map((f) => _FaqTile(faq: f)),
                ],

                if (prospectus.contacts.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('Contact', style: text.titleLarge),
                  const SizedBox(height: 12),
                  ...prospectus.contacts.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ContactCard(contact: c),
                    ),
                  ),
                ],

                if (institution.website != null || profile.socials.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (institution.website != null)
                        _LinkChip(label: 'Website', url: institution.website!),
                      ...profile.socials.entries.map(
                        (e) => _LinkChip(label: e.key, url: e.value),
                      ),
                    ],
                  ),
                ],

                // A page with nothing on it should say so rather than look broken.
                if (profile.completeness < 20 &&
                    prospectus.programs.isEmpty) ...[
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'This institution has not finished its page yet. You can '
                      'still message them or request a meeting.',
                      style: text.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(IconData, String, String)> _facts(Prospectus p) {
    final profile = p.profile;
    return [
      if (profile.costOfLivingDisplay != null)
        (Icons.payments_outlined, 'Living costs', profile.costOfLivingDisplay!),
      if (profile.studentCount != null)
        (
          Icons.groups_outlined,
          'Students',
          formatThousands(profile.studentCount!)
        ),
      if (profile.internationalStudentCount != null)
        (
          Icons.public_outlined,
          'International',
          formatThousands(profile.internationalStudentCount!)
        ),
      if (profile.foundedYear != null)
        (Icons.history_rounded, 'Founded', '${profile.foundedYear}'),
      if (profile.applicationFee != null)
        (
          Icons.receipt_long_outlined,
          'Application fee',
          '${profile.feeCurrency} ${profile.applicationFee!.round()}'
        ),
    ];
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _HeaderSliver extends StatelessWidget {
  final Prospectus prospectus;

  const _HeaderSliver({required this.prospectus});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photos = prospectus.photos;

    if (photos.isEmpty) {
      return SliverAppBar(
        pinned: true,
        backgroundColor: colors.background,
        title: Text(prospectus.institution.name,
            overflow: TextOverflow.ellipsis),
      );
    }

    final service = SupabaseService.instance;

    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      backgroundColor: colors.primary,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              itemCount: photos.length,
              itemBuilder: (context, i) => CachedNetworkImage(
                imageUrl: service.publicUrl(
                  bucket: AppConstants.bucketInstitutionMedia,
                  path: photos[i].storagePath!,
                ),
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: colors.primary),
              ),
            ),
            // So the back button and title stay legible over any photo.
            DecoratedBox(
              decoration: BoxDecoration(gradient: colors.heroGradient),
            ),
            if (photos.length > 1)
              Positioned(
                right: 14,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${photos.length} photos',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── The requirement that applies to this student ────────────────────────────

class _RequirementCard extends StatelessWidget {
  final EntryRequirement requirement;
  final String? country;

  const _RequirementCard({required this.requirement, this.country});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final countryName = AppConstants.homeCountries[country] ?? country;
    final heading = requirement.isCountrySpecific && countryName != null
        ? 'What you need, from $countryName'
        : 'What you need';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.infoLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 19, color: colors.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  heading,
                  style: text.titleMedium?.copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (requirement.qualification != null)
            _Line(icon: Icons.school_outlined, text: requirement.qualification!),
          _Line(icon: Icons.translate_rounded, text: requirement.englishDisplay),
          _Line(
            icon: Icons.stairs_outlined,
            text: 'Applies to ${requirement.levelLabel.toLowerCase()}',
          ),
          ...requirement.additional.map(
            (a) => _Line(icon: Icons.add_circle_outline, text: a),
          ),
          if (requirement.note != null) ...[
            const SizedBox(height: 8),
            Text(requirement.note!,
                style: text.bodySmall?.copyWith(height: 1.45)),
          ],
          if (!requirement.isCountrySpecific) ...[
            const SizedBox(height: 10),
            Text(
              // Says plainly that this is the general rule, so a student does
              // not read it as a decision about them specifically.
              'This is their general requirement — they have not published one '
              'for your country.',
              style: text.labelSmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Line({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: context.colors.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      );
}

// ── Intakes ─────────────────────────────────────────────────────────────────

class _IntakeStrip extends StatelessWidget {
  final List<Intake> intakes;

  const _IntakeStrip({required this.intakes});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: intakes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final intake = intakes[i];
          final soon = intake.isClosingSoon;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: soon ? colors.warningLight : colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: soon ? colors.warning : colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(intake.label, style: text.titleMedium),
                const SizedBox(height: 3),
                Text(
                  intake.daysToClose == null
                      ? 'No closing date published'
                      : soon
                          ? 'Closes in ${intake.daysToClose} days'
                          : 'Applications open',
                  style: text.bodySmall?.copyWith(
                    color: soon ? colors.warning : colors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

class _FactGrid extends StatelessWidget {
  final List<(IconData, String, String)> facts;

  const _FactGrid({required this.facts});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: facts
          .map(
            (fact) => Container(
              width: (MediaQuery.sizeOf(context).width - 50) / 2,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(fact.$1, size: 17, color: colors.accent),
                  const SizedBox(height: 8),
                  Text(fact.$3,
                      style: text.titleMedium, overflow: TextOverflow.ellipsis),
                  Text(fact.$2, style: text.bodySmall),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? body;

  const _Section({required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    if (body == null || body!.trim().isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          const SizedBox(height: 8),
          Text(body!, style: text.bodyMedium?.copyWith(height: 1.55)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Pill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ScholarshipCard extends StatelessWidget {
  final Scholarship scholarship;

  const _ScholarshipCard({required this.scholarship});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: scholarship.url == null
          ? null
          : () => launchUrl(Uri.parse(scholarship.url!),
              mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.warningLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_rounded, size: 18, color: colors.warning),
                const SizedBox(width: 9),
                Expanded(child: Text(scholarship.name, style: text.titleMedium)),
                Text(
                  scholarship.valueDisplay,
                  style: text.titleSmall?.copyWith(color: colors.warning),
                ),
              ],
            ),
            if (scholarship.criteria != null) ...[
              const SizedBox(height: 8),
              Text(scholarship.criteria!,
                  style: text.bodySmall?.copyWith(height: 1.45)),
            ],
            if (scholarship.deadline != null) ...[
              const SizedBox(height: 8),
              Text(
                'Closes ${_formatDate(scholarship.deadline!)}',
                style: text.labelSmall?.copyWith(color: colors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Step extends StatelessWidget {
  final int index;
  final ApplicationStep step;

  const _Step({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: text.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: text.titleMedium),
                if (step.detail != null)
                  Text(step.detail!,
                      style: text.bodySmall?.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final Faq faq;

  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Theme(
      // The default divider on an ExpansionTile fights the card borders used
      // everywhere else on this page.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(faq.question, style: text.titleMedium),
        children: [
          Text(faq.answer, style: text.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;

  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.role, style: text.titleMedium),
                if (contact.name != null)
                  Text(contact.name!, style: text.bodySmall),
                if (contact.email != null)
                  Text(contact.email!,
                      style: text.bodySmall?.copyWith(color: colors.accent)),
              ],
            ),
          ),
          if (contact.email != null)
            IconButton(
              tooltip: 'Email',
              onPressed: () =>
                  launchUrl(Uri.parse('mailto:${contact.email}')),
              icon: const Icon(Icons.mail_outline_rounded, size: 19),
            ),
          if (contact.phone != null)
            IconButton(
              tooltip: 'Call',
              onPressed: () => launchUrl(Uri.parse('tel:${contact.phone}')),
              icon: const Icon(Icons.call_outlined, size: 19),
            ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  final String label;
  final String url;

  const _LinkChip({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ActionChip(
      avatar: Icon(Icons.open_in_new_rounded, size: 14, color: colors.accent),
      label: Text(label[0].toUpperCase() + label.substring(1)),
      onPressed: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      backgroundColor: colors.surface,
      side: BorderSide(color: colors.border),
    );
  }
}
