import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../passport/providers/passport_provider.dart';
import '../../social/models/post.dart';
import '../../social/providers/feed_provider.dart';
import '../../social/widgets/post_card.dart';
import '../models/program.dart';
import '../providers/discover_provider.dart';
import '../widgets/institution_tile.dart';

/// Browse the directory. Search and filtering run server-side, so a student on
/// a metered connection is not downloading a catalogue to filter locally.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  late final TabController _tabs = TabController(length: 3, vsync: this);

  /// Post results are held here rather than in a provider: they belong to this
  /// screen's search box and nothing else reads them.
  List<Post>? _posts;
  bool _searchingPosts = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DiscoverProvider>().load();
      context.read<PassportProvider>().load();
      context.read<FeedProvider>().load(
            const FeedTab(label: 'For you', kind: FeedKind.forYou),
          );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    setState(() {});
    // Moving to Posts with something already typed should show results, not an
    // empty tab waiting for another keystroke.
    if (_tabs.index == 2 && _searchController.text.trim().isNotEmpty) {
      _searchPosts(_searchController.text);
    }
  }

  void _onScroll() {
    // Only programmes page; the other two tabs fetch a single capped set.
    if (_tabs.index != 0) return;
    // Prefetch before the student actually hits the bottom.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      context.read<DiscoverProvider>().loadMore();
    }
  }

  Future<void> _searchPosts(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _posts = null);
      return;
    }
    setState(() => _searchingPosts = true);
    final results = await context.read<FeedProvider>().searchPosts(query);
    if (!mounted) return;
    setState(() {
      _posts = results;
      _searchingPosts = false;
    });
  }

  /// Debounced so typing does not fire a query per keystroke.
  ///
  /// One box drives all three tabs: the provider's `search` filters programmes
  /// *and* institutions server-side, and posts go through their own RPC.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<DiscoverProvider>().search(value.trim());
      if (_tabs.index == 2) _searchPosts(value);
    });
  }

  Future<void> _openFilters() async {
    final provider = context.read<DiscoverProvider>();
    final fields = context.read<PassportProvider>().fields;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (_, scrollController) => _FilterSheet(
          provider: provider,
          fieldOptions: {for (final f in fields) f.slug: f.label},
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<DiscoverProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: colors.divider,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorColor: colors.accent,
              indicatorWeight: 3,
              labelColor: colors.textPrimary,
              unselectedLabelColor: colors.textSecondary,
              tabs: const [
                Tab(text: 'Programs'),
                Tab(text: 'Institutions'),
                Tab(text: 'Posts'),
              ],
            ),
          ),
        ),
        actions: [
          if (_tabs.index != 2)
            IconButton(
              tooltip: 'Filters',
              onPressed: _openFilters,
              icon: provider.hasFilters
                  ? Badge(
                      backgroundColor: colors.accent,
                      child: const Icon(Icons.tune_rounded),
                    )
                  : const Icon(Icons.tune_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: switch (_tabs.index) {
                  0 => 'Search programs, degrees, subjects...',
                  1 => 'Search universities & colleges...',
                  _ => 'Search university posts & updates...',
                },
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          provider.search('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),

          // Quick filter chips (for Programs and Institutions tabs)
          if (_tabs.index != 2) ...[
            _quickFilterBar(context, provider),
            const SizedBox(height: 10),
          ],

          // The result count belongs to whichever list is showing.
          if (provider.hasFilters && _tabs.index != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (_tabs.index) {
                        1 => '${provider.institutions.length} institution'
                            '${provider.institutions.length == 1 ? '' : 's'}',
                        _ => '${provider.programs.length} result'
                            '${provider.programs.length == 1 ? '' : 's'}',
                      },
                      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      _searchController.clear();
                      provider.clearFilters();
                    },
                    child: Text(
                      'Clear filters',
                      style: text.bodySmall?.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _programsTab(context, provider),
                _institutionsTab(context, provider),
                _postsTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickFilterBar(BuildContext context, DiscoverProvider provider) {
    final colors = context.colors;
    final currentCountry = provider.countryFilter;
    final currentLevel = provider.levelFilter;
    final scholarshipOnly = provider.scholarshipOnly;
    final isAllSelected = currentCountry == null && currentLevel == null && !scholarshipOnly;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          // All chip
          ActionChip(
            label: const Text('All'),
            avatar: isAllSelected
                ? Icon(Icons.check_rounded, size: 15, color: colors.accent)
                : null,
            backgroundColor: isAllSelected
                ? colors.accent.withValues(alpha: 0.15)
                : colors.surfaceVariant,
            side: BorderSide(
              color: isAllSelected ? colors.accent : colors.border,
            ),
            onPressed: () {
              _searchController.clear();
              provider.clearFilters();
            },
          ),
          const SizedBox(width: 8),

          // Popular destinations
          _countryChip(context, provider, 'CA', '🇨🇦 Canada'),
          const SizedBox(width: 8),
          _countryChip(context, provider, 'GB', '🇬🇧 UK'),
          const SizedBox(width: 8),
          _countryChip(context, provider, 'US', '🇺🇸 USA'),
          const SizedBox(width: 8),
          _countryChip(context, provider, 'DE', '🇩🇪 Germany'),
          const SizedBox(width: 8),
          _countryChip(context, provider, 'AU', '🇦🇺 Australia'),
          const SizedBox(width: 8),
          _countryChip(context, provider, 'IE', '🇮🇪 Ireland'),
          const SizedBox(width: 8),

          // Degree level chips
          _levelChip(context, provider, 'undergraduate', 'Bachelor’s'),
          const SizedBox(width: 8),
          _levelChip(context, provider, 'postgraduate', 'Master’s'),
          const SizedBox(width: 8),
          _levelChip(context, provider, 'doctorate', 'Doctorate'),
          const SizedBox(width: 8),

          // Scholarships
          ActionChip(
            avatar: Icon(
              Icons.school_outlined,
              size: 15,
              color: scholarshipOnly ? colors.accent : colors.textSecondary,
            ),
            label: const Text('Scholarships'),
            backgroundColor: scholarshipOnly
                ? colors.accent.withValues(alpha: 0.15)
                : colors.surfaceVariant,
            side: BorderSide(
              color: scholarshipOnly ? colors.accent : colors.border,
            ),
            onPressed: () => provider.setFilters(scholarshipOnly: !scholarshipOnly),
          ),
        ],
      ),
    );
  }

  Widget _countryChip(BuildContext context, DiscoverProvider provider, String code, String label) {
    final colors = context.colors;
    final isSelected = provider.countryFilter == code;

    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected
          ? colors.accent.withValues(alpha: 0.15)
          : colors.surfaceVariant,
      side: BorderSide(
        color: isSelected ? colors.accent : colors.border,
      ),
      onPressed: () {
        if (isSelected) {
          provider.setFilters(clearCountry: true);
        } else {
          provider.setFilters(country: code);
        }
      },
    );
  }

  Widget _levelChip(BuildContext context, DiscoverProvider provider, String level, String label) {
    final colors = context.colors;
    final isSelected = provider.levelFilter == level;

    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected
          ? colors.accent.withValues(alpha: 0.15)
          : colors.surfaceVariant,
      side: BorderSide(
        color: isSelected ? colors.accent : colors.border,
      ),
      onPressed: () {
        if (isSelected) {
          provider.setFilters(clearLevel: true);
        } else {
          provider.setFilters(level: level);
        }
      },
    );
  }

  /// What institutions are actually saying.
  Widget _postsTab(BuildContext context) {
    if (_searchingPosts) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      final posts = _posts;
      if (posts == null || posts.isEmpty) {
        return ListView(
          children: [
            const SizedBox(height: 50),
            EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing posted about "$query"',
              message: 'Try a broader word, or follow an institution so their '
                  'updates reach your feed.',
              actionLabel: 'Clear search',
              onAction: () {
                _searchController.clear();
                _searchPosts('');
              },
            ),
          ],
        );
      }
      return ListView.builder(
        padding: EdgeInsets.only(bottom: AppChrome.navClearance(context)),
        itemCount: posts.length,
        itemBuilder: (_, i) => PostCard(
          post: posts[i],
          onTap: () => context.push('${AppConstants.routePost}/${posts[i].id}'),
          onAuthorTap: (h) => context.push('${AppConstants.routeHandle}/$h'),
        ),
      );
    }

    // Default when no search query is typed: show trending / recent university posts!
    final feed = context.watch<FeedProvider>();
    final defaultTab = const FeedTab(label: 'For you', kind: FeedKind.forYou);
    final posts = feed.postsFor(defaultTab);

    if (feed.isLoading(defaultTab) && posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (posts.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 50),
          EmptyState(
            icon: Icons.forum_outlined,
            title: 'No university posts yet',
            message: 'Universities post scholarship deadlines, entry requirements, '
                'and open days here. Check back soon or browse programs!',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => feed.load(defaultTab, refresh: true),
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: AppChrome.navClearance(context)),
        itemCount: posts.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      size: 18, color: ctx.colors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Latest university updates & discussions',
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ctx.colors.textSecondary,
                        ),
                  ),
                ],
              ),
            );
          }
          final post = posts[i - 1];
          return PostCard(
            post: post,
            onTap: () => ctx.push('${AppConstants.routePost}/${post.id}'),
            onAuthorTap: (h) => ctx.push('${AppConstants.routeHandle}/$h'),
          );
        },
      ),
    );
  }

  /// Browse organisations directly — the half of discovery that was fetched
  /// on every load and never rendered.
  Widget _institutionsTab(BuildContext context, DiscoverProvider provider) {
    if (provider.loading && provider.institutions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.institutions.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 50),
          EmptyState(
            icon: Icons.apartment_outlined,
            title: provider.hasFilters ? 'No institutions match your filters' : 'Discover universities',
            message: provider.hasFilters
                ? 'Try selecting a different destination or clearing your search.'
                : 'Registered universities appear here. Explore their courses, tuition, and admissions.',
            actionLabel: provider.hasFilters ? 'Clear filters' : null,
            onAction: provider.hasFilters
                ? () {
                    _searchController.clear();
                    provider.clearFilters();
                  }
                : null,
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, AppChrome.navClearance(context)),
        itemCount: provider.institutions.length,
        itemBuilder: (_, i) {
          final institution = provider.institutions[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InstitutionTile(
              institution: institution,
              onTap: () => context.push(
                  '${AppConstants.routeInstitution}/${institution.id}'),
            ),
          );
        },
      ),
    );
  }

  Widget _programsTab(BuildContext context, DiscoverProvider provider) {
    if (provider.loading && provider.programs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.programs.isEmpty) {
      return ErrorState(message: provider.error!, onRetry: provider.load);
    }
    if (provider.programs.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 50),
          EmptyState(
            icon: Icons.school_outlined,
            title: provider.hasFilters
                ? 'No programs match your filters'
                : 'Explore universities & courses',
            message: provider.hasFilters
                ? 'Try clearing or widening your destination and level filters to see available courses.'
                : 'Browse participating universities or check university updates to see what is on offer.',
            actionLabel: provider.hasFilters ? 'Clear filters' : 'View universities',
            onAction: provider.hasFilters
                ? () {
                    _searchController.clear();
                    provider.clearFilters();
                  }
                : () {
                    _tabs.animateTo(1);
                  },
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, AppChrome.navClearance(context)),
        itemCount:
            provider.programs.length + (provider.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= provider.programs.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final program = provider.programs[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ProgramTile(
              program: program,
              isSaved: provider.isSaved(program.id),
              onToggleSave: () => provider.toggleSaved(program.id),
            ),
          );
        },
      ),
    );
  }
}


/// A program row. Shared with the institution screen, so it lives here rather
/// than being duplicated.
class ProgramTile extends StatelessWidget {
  final Program program;
  final bool isSaved;
  final VoidCallback? onToggleSave;

  const ProgramTile({
    super.key,
    required this.program,
    this.isSaved = false,
    this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final institution = program.institution;

    return InkWell(
      onTap: () => context.push('${AppConstants.routeProgram}/${program.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InstitutionAvatar(
              logoUrl: institution?.logoUrl,
              initials: institution?.initials ?? '?',
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    program.name,
                    style: text.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          institution == null
                              ? ''
                              : '${institution.name} · ${institution.location}',
                          style: text.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (institution?.isVerified ?? false) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded,
                            size: 13, color: colors.success),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MiniChip(
                        label: program.levelLabel,
                        color: colors.textSecondary,
                        background: colors.surfaceVariant,
                      ),
                      _MiniChip(
                        label: program.tuitionDisplay,
                        color: colors.textSecondary,
                        background: colors.surfaceVariant,
                      ),
                      if (program.scholarshipAvailable)
                        _MiniChip(
                          label: 'Scholarships',
                          color: colors.warning,
                          background: colors.warningLight,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (onToggleSave != null)
              IconButton(
                tooltip: isSaved ? 'Saved' : 'Save',
                onPressed: onToggleSave,
                icon: Icon(
                  isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  size: 20,
                  color: isSaved ? colors.accent : colors.textLight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _MiniChip({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w500),
        ),
      );
}

class _FilterSheet extends StatefulWidget {
  final DiscoverProvider provider;
  final Map<String, String> fieldOptions;
  final ScrollController scrollController;

  const _FilterSheet({
    required this.provider,
    required this.fieldOptions,
    required this.scrollController,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _level;
  String? _field;
  String? _country;
  bool _scholarshipOnly = false;

  @override
  void initState() {
    super.initState();
    _level = widget.provider.levelFilter;
    _field = widget.provider.fieldFilter;
    _country = widget.provider.countryFilter;
    _scholarshipOnly = widget.provider.scholarshipOnly;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Filters', style: text.headlineSmall),
              const SizedBox(height: 20),
              _SingleSelect(
                label: 'Destination',
                options: AppConstants.popularDestinations,
                value: _country,
                onChanged: (v) => setState(() => _country = v),
              ),
              const SizedBox(height: 20),
              _SingleSelect(
                label: 'Study level',
                options: AppConstants.studyLevels,
                value: _level,
                onChanged: (v) => setState(() => _level = v),
              ),
              const SizedBox(height: 20),
              _SingleSelect(
                label: 'Field of study',
                options: widget.fieldOptions,
                value: _field,
                onChanged: (v) => setState(() => _field = v),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scholarships available only'),
                value: _scholarshipOnly,
                onChanged: (v) => setState(() => _scholarshipOnly = v),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.provider.clearFilters();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.provider.setFilters(
                        level: _level,
                        field: _field,
                        country: _country,
                        scholarshipOnly: _scholarshipOnly,
                        clearLevel: _level == null,
                        clearField: _field == null,
                        clearCountry: _country == null,
                      );
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SingleSelect extends StatelessWidget {
  final String label;
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _SingleSelect({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((entry) {
            final selected = value == entry.key;
            return FilterChip(
              label: Text(entry.value),
              selected: selected,
              showCheckmark: false,
              // Tapping the active chip clears it, which is the expected
              // behaviour for a single-select chip group.
              onSelected: (_) => onChanged(selected ? null : entry.key),
              backgroundColor: colors.surface,
              selectedColor: colors.accent,
              side: BorderSide(color: selected ? colors.accent : colors.border),
              labelStyle: text.bodyMedium?.copyWith(
                color: selected ? context.colors.onAccent : colors.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
