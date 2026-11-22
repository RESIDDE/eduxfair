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
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../auth/providers/auth_provider.dart';
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
        followerCount =
            (followStatus['follower_count'] as num?)?.toInt() ?? followerCount;
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
        params: {'p_institution_id': institution.id, 'p_follow': !_isFollowing},
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

  // ── Section anchors, for the jump bar ─────────────────────────────────
  final _overviewKey = GlobalKey();
  final _programmesKey = GlobalKey();
  final _scholarshipsKey = GlobalKey();
  final _applyKey = GlobalKey();
  final _faqKey = GlobalKey();
  final _contactKey = GlobalKey();

  void _jumpTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
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
    final facts = _facts(prospectus);
    // Staff reach this page from their own "see it as students do" preview.
    // Follow, Message and Meet are a student's actions — and for staff they
    // led to student-only screens — so the preview shows a note instead.
    final isStudent = context.watch<AuthProvider>().user?.isStudent ?? true;
    final hasOverview =
        facts.isNotEmpty ||
        [
          profile.about,
          profile.campusLife,
          profile.accommodation,
        ].any((t) => (t ?? '').trim().isNotEmpty) ||
        profile.rankings.isNotEmpty ||
        profile.accreditation.isNotEmpty;

    final jumps = <(String, GlobalKey)>[
      if (hasOverview) ('Overview', _overviewKey),
      if (prospectus.programs.isNotEmpty) ('Programmes', _programmesKey),
      if (prospectus.scholarships.isNotEmpty)
        ('Scholarships', _scholarshipsKey),
      if (profile.applicationSteps.isNotEmpty) ('How to apply', _applyKey),
      if (prospectus.faqs.isNotEmpty) ('Questions', _faqKey),
      if (prospectus.contacts.isNotEmpty) ('Contact', _contactKey),
    ];

    // The back button floats over the cover, like a place card in Maps, and
    // stays put as the page scrolls under it.
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Cover and identity ───────────────────────────────────────────
          SliverToBoxAdapter(child: _Cover(prospectus: prospectus)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 54, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              institution.name,
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (institution.isVerified) ...[
                            const SizedBox(width: 6),
                            const VerifiedBadge(
                              subject: VerifiedSubject.institution,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                      if (profile.tagline != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.tagline!,
                          style: text.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              institution.location,
                              style: text.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!institution.isVerified &&
                          institution.verificationStatus == 'pending') ...[
                        const SizedBox(height: 8),
                        VerificationStatusChip(
                          status: institution.verificationStatus,
                          subject: VerifiedSubject.institution,
                        ),
                      ],

                      // ── Stats ─────────────────────────────────────
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _Stat(
                            value: formatThousands(_followerCount),
                            label: _followerCount == 1
                                ? 'Follower'
                                : 'Followers',
                          ),
                          if (prospectus.programs.isNotEmpty)
                            _Stat(
                              value: '${prospectus.programs.length}',
                              label: prospectus.programs.length == 1
                                  ? 'Programme'
                                  : 'Programmes',
                            ),
                          if (profile.studentCount != null)
                            _Stat(
                              value: _compact(profile.studentCount!),
                              label: 'Students',
                            ),
                          if (profile.foundedYear != null)
                            _Stat(
                              value: '${profile.foundedYear}',
                              label: 'Founded',
                            ),
                        ],
                      ),

                      // ── Actions ───────────────────────────────────
                      if (!isStudent) ...[
                        const SizedBox(height: 18),
                        const _PreviewNote(),
                      ] else ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _ActionPill(
                                label: _isFollowing ? 'Following' : 'Follow',
                                icon: _isFollowing
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                primary: !_isFollowing,
                                busy: _busyFollow,
                                onTap: _busyFollow ? null : _toggleFollow,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ActionPill(
                                label: 'Message',
                                icon: Icons.chat_bubble_outline_rounded,
                                onTap: _message,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ActionPill(
                                label: 'Meet',
                                icon: Icons.event_available_outlined,
                                onTap: () => context.push(
                                  '${AppConstants.routeAppointmentRequest}'
                                  '?institution=${institution.id}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          // ── Jump bar ─────────────────────────────────────────────────────
          // Pills that scroll to a section — the page is long, and a student
          // usually came for one part of it.
          if (jumps.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: jumps.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => Pressable(
                    onTap: () => _jumpTo(jumps[i].$2),
                    semanticLabel: 'Go to ${jumps[i].$1}',
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        jumps[i].$1,
                        style: text.labelLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            sliver: SliverList.list(
              children: [
                if (prospectus.requirementForMe != null) ...[
                  const SizedBox(height: 16),
                  _RequirementCard(
                    requirement: prospectus.requirementForMe!,
                    country: prospectus.resolvedForCountry,
                  ),
                ],

                if (prospectus.openIntakes.isNotEmpty) ...[
                  _Heading('Intakes'),
                  _IntakeStrip(intakes: prospectus.openIntakes),
                ],

                // ── Overview ─────────────────────────────────────────────
                if (hasOverview) ...[
                  _Heading('Overview', anchor: _overviewKey),
                  if (facts.isNotEmpty) _FactGrid(facts: facts),
                  _Section(title: 'About', body: profile.about),
                  _Section(title: 'Campus life', body: profile.campusLife),
                  _Section(title: 'Accommodation', body: profile.accommodation),
                  if (profile.rankings.isNotEmpty ||
                      profile.accreditation.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Recognition',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...profile.rankings.map(
                          (r) => _Pill(
                            label: r.display,
                            icon: Icons.leaderboard_outlined,
                          ),
                        ),
                        ...profile.accreditation.map(
                          (a) => _Pill(label: a, icon: Icons.verified_outlined),
                        ),
                      ],
                    ),
                  ],
                ],

                if (prospectus.programs.isNotEmpty) ...[
                  _Heading(
                    'Programmes',
                    count: prospectus.programs.length,
                    anchor: _programmesKey,
                  ),
                  ...prospectus.programs.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ProgramTile(program: p),
                    ),
                  ),
                ],

                if (prospectus.scholarships.isNotEmpty) ...[
                  _Heading(
                    'Scholarships',
                    count: prospectus.scholarships.length,
                    anchor: _scholarshipsKey,
                  ),
                  ...prospectus.scholarships.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ScholarshipCard(scholarship: s),
                    ),
                  ),
                ],

                if (profile.applicationSteps.isNotEmpty) ...[
                  _Heading('How to apply', anchor: _applyKey),
                  ...profile.applicationSteps.asMap().entries.map(
                    (e) => _Step(
                      index: e.key + 1,
                      step: e.value,
                      last: e.key == profile.applicationSteps.length - 1,
                    ),
                  ),
                ],

                if (prospectus.faqs.isNotEmpty) ...[
                  _Heading('Questions students ask', anchor: _faqKey),
                  _Grouped(
                    children: [
                      for (final f in prospectus.faqs) _FaqTile(faq: f),
                    ],
                  ),
                ],

                if (prospectus.contacts.isNotEmpty) ...[
                  _Heading('Contact', anchor: _contactKey),
                  _Grouped(
                    children: [
                      for (final c in prospectus.contacts)
                        _ContactRow(contact: c),
                    ],
                  ),
                ],

                if (institution.website != null ||
                    profile.socials.isNotEmpty) ...[
                  const SizedBox(height: 20),
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

                if (profile.completeness < 20 &&
                    prospectus.programs.isEmpty) ...[
                  const SizedBox(height: 24),
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

  /// 41000 -> 41k: a stat row has room for a glance, not a figure.
  static String _compact(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}m';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 || n >= 10000 ? 0 : 1)}k';
    }
    return '$n';
  }

  List<(IconData, String, String)> _facts(Prospectus p) {
    final profile = p.profile;
    return [
      if (profile.costOfLivingDisplay != null)
        (
          Icons.payments_outlined,
          'Living costs a year',
          profile.costOfLivingDisplay!,
        ),
      if (profile.internationalStudentCount != null)
        (
          Icons.public_outlined,
          'International students',
          formatThousands(profile.internationalStudentCount!),
        ),
      if (profile.applicationFee != null)
        (
          Icons.receipt_long_outlined,
          'Application fee',
          '${profile.feeCurrency} ${formatThousands(profile.applicationFee!.round())}',
        ),
      if (profile.studentCount != null)
        (
          Icons.groups_outlined,
          'Students',
          formatThousands(profile.studentCount!),
        ),
    ];
  }
}

/// The cover, with the logo overlapping its lower edge.
///
/// One block rather than a pinned header plus a logo below it: a pinned
/// header is painted over everything that scrolls, so the overlapping logo was
/// cut off by it. Photos swipe; with none, a quiet backdrop keeps the shape.
class _Cover extends StatefulWidget {
  final Prospectus prospectus;

  const _Cover({required this.prospectus});

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photos = widget.prospectus.photos;
    final institution = widget.prospectus.institution;
    final service = SupabaseService.instance;
    final top = MediaQuery.paddingOf(context).top;
    final height = (photos.isEmpty ? 110.0 : 220.0) + top;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: photos.isEmpty
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.surfaceVariant, colors.background],
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) => CachedNetworkImage(
                        imageUrl: service.publicUrl(
                          bucket: AppConstants.bucketInstitutionMedia,
                          path: photos[i].storagePath!,
                        ),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: colors.surfaceVariant),
                      ),
                    ),
                    // A soft shade at the top so the back button and the
                    // status bar stay legible over a bright photo.
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                    if (photos.length > 1)
                      Positioned(
                        right: 16,
                        bottom: 14,
                        child: Row(
                          children: [
                            for (var i = 0; i < photos.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(left: 5),
                                width: i == _page ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: i == _page ? 1 : 0.55,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        // Ringed in the page colour so it reads as sitting on the cover.
        Positioned(
          left: 16,
          bottom: -44,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.background,
              shape: BoxShape.circle,
            ),
            child: InstitutionAvatar(
              logoUrl: institution.logoUrl,
              initials: institution.initials,
              size: 84,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────────

class _Heading extends StatelessWidget {
  final String title;
  final int? count;
  final GlobalKey? anchor;

  const _Heading(this.title, {this.count, this.anchor});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      key: anchor,
      padding: const EdgeInsets.only(top: 32, bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: text.titleMedium?.copyWith(
                color: context.colors.textLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Follow, Message, Meet: one shape, the main one filled in the text colour.
class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final bool busy;
  final VoidCallback? onTap;

  const _ActionPill({
    required this.label,
    required this.icon,
    this.primary = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = primary ? colors.background : colors.textPrimary;
    return Pressable(
      onTap: onTap,
      haptic: primary ? HapticKind.impact : HapticKind.selection,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        decoration: BoxDecoration(
          color: primary ? colors.textPrimary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else
              Icon(icon, size: 17, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded group with hairlines between rows.
class _Grouped extends StatelessWidget {
  final List<Widget> children;
  const _Grouped({required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, color: colors.divider, indent: 16),
          ],
        ],
      ),
    );
  }
}

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
        ? 'What you need, applying from $countryName'
        : 'What you need';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (requirement.qualification != null)
            _Line(text: requirement.qualification!),
          _Line(text: requirement.englishDisplay),
          _Line(text: 'Applies to ${requirement.levelLabel.toLowerCase()}'),
          ...requirement.additional.map((a) => _Line(text: a)),
          if (requirement.note != null) ...[
            const SizedBox(height: 6),
            Text(
              requirement.note!,
              style: text.bodySmall?.copyWith(
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (!requirement.isCountrySpecific) ...[
            const SizedBox(height: 10),
            Text(
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
  final String text;

  const _Line({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_circle_rounded,
            size: 17,
            color: context.colors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _IntakeStrip extends StatelessWidget {
  final List<Intake> intakes;

  const _IntakeStrip({required this.intakes});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: intakes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final intake = intakes[i];
          final soon = intake.isClosingSoon;

          return Container(
            constraints: const BoxConstraints(minWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  intake.label,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Colour where it means something: closing soon.
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: soon ? colors.warning : colors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      intake.daysToClose == null
                          ? 'Open'
                          : soon
                          ? 'Closes in ${intake.daysToClose} days'
                          : 'Applications open',
                      style: text.bodySmall?.copyWith(
                        color: soon ? colors.warning : colors.textSecondary,
                        fontWeight: soon ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FactGrid extends StatelessWidget {
  final List<(IconData, String, String)> facts;

  const _FactGrid({required this.facts});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        for (final fact in facts)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(fact.$1, size: 18, color: colors.textSecondary),
                const Spacer(),
                Text(
                  fact.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  fact.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A titled paragraph that folds after a few lines, with "Read more".
class _Section extends StatefulWidget {
  final String title;
  final String? body;

  const _Section({required this.title, this.body});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final body = widget.body?.trim() ?? '';
    if (body.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final long = body.length > 260;

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Text(
              body,
              maxLines: _open || !long ? null : 4,
              overflow: _open || !long ? null : TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(height: 1.55),
            ),
          ),
          if (long)
            GestureDetector(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _open ? 'Show less' : 'Read more',
                  style: text.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
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

    return Pressable.surface(
      onTap: scholarship.url == null
          ? null
          : () => launchUrl(
              Uri.parse(scholarship.url!),
              mode: LaunchMode.externalApplication,
            ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    scholarship.name,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  scholarship.valueDisplay,
                  style: text.titleMedium?.copyWith(
                    color: colors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (scholarship.criteria != null) ...[
              const SizedBox(height: 6),
              Text(
                scholarship.criteria!,
                style: text.bodySmall?.copyWith(
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (scholarship.deadline != null || scholarship.url != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (scholarship.deadline != null)
                    Text(
                      'Closes ${_formatDate(scholarship.deadline!)}',
                      style: text.labelMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  if (scholarship.url != null)
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// One step, joined to the next by a line — a timeline, read top to bottom.
class _Step extends StatelessWidget {
  final int index;
  final ApplicationStep step;
  final bool last;

  const _Step({required this.index, required this.step, this.last = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: text.labelMedium?.copyWith(
                    color: colors.background,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: colors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (step.detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.detail!,
                      style: text.bodySmall?.copyWith(
                        height: 1.45,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
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
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: context.colors.textSecondary,
        collapsedIconColor: context.colors.textSecondary,
        title: Text(
          faq.question,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        children: [
          Text(
            faq.answer,
            style: text.bodyMedium?.copyWith(
              height: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final Contact contact;

  const _ContactRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.role,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (contact.name != null)
                  Text(
                    contact.name!,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                if (contact.email != null)
                  Text(
                    contact.email!,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (contact.email != null)
            _RoundIcon(
              icon: Icons.mail_outline_rounded,
              tooltip: 'Email ${contact.role}',
              onTap: () => launchUrl(Uri.parse('mailto:${contact.email}')),
            ),
          if (contact.phone != null)
            _RoundIcon(
              icon: Icons.call_outlined,
              tooltip: 'Call ${contact.role}',
              onTap: () => launchUrl(Uri.parse('tel:${contact.phone}')),
            ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        semanticLabel: tooltip,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.colors.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: context.colors.textPrimary),
        ),
      ),
    ),
  );
}

class _LinkChip extends StatelessWidget {
  final String label;
  final String url;

  const _LinkChip({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label[0].toUpperCase() + label.substring(1),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.arrow_outward_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of Follow / Message / Meet when staff preview their page.
class _PreviewNote extends StatelessWidget {
  const _PreviewNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 18, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is how students see your page. They can follow you, '
              'message you and book a meeting from here.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(height: 1.4, color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
