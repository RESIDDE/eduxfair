import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/surface.dart';
import '../../meet/models/space.dart';
import '../../meet/providers/spaces_provider.dart';

/// The Spaces tab.
///
/// Replaces the placeholder that promised exactly this: "Institutions and
/// embassies will run admissions hours, scholarship Q&As and country briefings
/// here — drop in, listen, and raise your hand to ask."
///
/// Joining is listening. Nobody is identified by being here, which is the one
/// thing the copy on the card has to make clear before they tap.
class SpacesScreen extends StatefulWidget {
  const SpacesScreen({super.key});

  @override
  State<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends State<SpacesScreen> {
  @override
  void initState() {
    super.initState();
    final spaces = context.read<SpacesProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      spaces.load();
      // A session going live has to arrive without a pull-to-refresh, because
      // "drop in" is what this tab promises.
      spaces.subscribe();
    });
  }

  @override
  void dispose() {
    context.read<SpacesProvider>().unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final spaces = context.watch<SpacesProvider>();

    final live = spaces.live;
    final upcoming = spaces.upcoming;

    return Scaffold(
      appBar: AppBar(title: const Text('Spaces')),
      body: RefreshIndicator(
        onRefresh: spaces.load,
        child: spaces.loading && spaces.spaces.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : (live.isEmpty && upcoming.isEmpty)
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: const [
                      SizedBox(height: 40),
                      EmptyState(
                        icon: Icons.podcasts_outlined,
                        title: 'Nothing live right now',
                        message:
                            'Institutions and embassies run admissions hours, '
                            'scholarship Q&As and country briefings here. Pull '
                            'down to check again.',
                      ),
                    ],
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, AppChrome.navClearance(context)),
                    children: [
                      if (live.isNotEmpty) ...[
                        _SectionLabel('Live now', color: colors.error),
                        for (final space in live)
                          _SpaceCard(space: space, live: true),
                      ],
                      if (upcoming.isNotEmpty) ...[
                        const _SectionLabel('Coming up'),
                        for (final space in upcoming)
                          _SpaceCard(space: space),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const _SectionLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color ?? colors.textSecondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
          ),
        ],
      ),
    );
  }
}

String _initial(String? name) =>
    (name == null || name.isEmpty) ? '?' : name[0].toUpperCase();

class _SpaceCard extends StatelessWidget {
  final Space space;
  final bool live;

  const _SpaceCard({required this.space, this.live = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final canJoin = live || space.isOpen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: canJoin
            ? () => context.push(
                '${AppConstants.routeCall}/space/${space.id}')
            : null,
        child: SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InstitutionAvatar(
                    logoUrl: space.institutionLogoUrl,
                    initials: _initial(space.institutionName),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          space.institutionName ?? 'An institution',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Not labelLarge: that is `onAccent`, a filled
                          // button's text colour, which is white here.
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          space.kindLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (live)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.errorLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'LIVE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.error,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(space.title, style: Theme.of(context).textTheme.titleMedium),
              if (space.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  space.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.textSecondary, height: 1.4),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14, color: colors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      live
                          ? 'Happening now · ${space.durationMin} min'
                          : '${formatDateTime(space.scheduledFor)} · '
                              '${space.durationMin} min',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ),
                  if (canJoin)
                    FilledButton.icon(
                      onPressed: () => context.push(
                          '${AppConstants.routeCall}/space/${space.id}'),
                      icon: const Icon(Icons.headphones_rounded, size: 16),
                      label: const Text('Listen in'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              if (canJoin) ...[
                const SizedBox(height: 10),
                Text(
                  space.requiresAdmission
                      ? 'You will wait for the host to let you in. Listening '
                          'does not share who you are.'
                      : 'Listening does not share who you are — only speaking '
                          'or asking a question does.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.textLight, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
