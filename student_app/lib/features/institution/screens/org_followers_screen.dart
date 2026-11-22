import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../widgets/org_ui.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/screens/chat_screen.dart';
import '../models/org_follower.dart';
import '../providers/institution_provider.dart';

/// The list of prospective students following this institution.
///
/// Students who follow receive the institution's updates and announcements
/// in their social Following feed tab.
class OrgFollowersScreen extends StatefulWidget {
  const OrgFollowersScreen({super.key});

  @override
  State<OrgFollowersScreen> createState() => _OrgFollowersScreenState();
}

class _OrgFollowersScreenState extends State<OrgFollowersScreen> {
  final _service = SupabaseService.instance;
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<OrgFollower> _followers = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final institutionId = context.read<InstitutionProvider>().institutionId;
    if (institutionId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _service.client.rpc(
        'my_institution_followers',
        params: {'p_institution_id': institutionId},
      );

      if (!mounted) return;
      setState(() {
        _followers = (res as List)
            .map((r) => OrgFollower.fromMap((r as Map).cast<String, dynamic>()))
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

  List<OrgFollower> get _filteredFollowers {
    if (_search.trim().isEmpty) return _followers;
    final q = _search.toLowerCase().trim();
    return _followers.where((f) {
      return f.fullName.toLowerCase().contains(q) ||
          (f.country != null && f.country!.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _messageStudent(OrgFollower follower) async {
    final institution = context.read<InstitutionProvider>().institution;
    if (institution == null) return;

    final messages = context.read<MessagesProvider>();
    final conversationId = await messages.openConversation(
      institutionId: institution.id,
      studentId: follower.studentId,
      subject: 'Message from ${institution.name}',
    );

    if (!mounted) return;
    if (conversationId != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          title: follower.fullName.isNotEmpty ? follower.fullName : 'Student',
        ),
      ));
    } else if (messages.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messages.error!),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final followers = _filteredFollowers;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Followers'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _followers.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No followers yet',
                      message: 'When students follow your page they appear '
                          'here, and your posts reach their Following feed.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 40),
                        children: [
                          // The number is the point of the screen, so it is
                          // set large and plain rather than in a tinted tile.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatThousands(_followers.length),
                                  style: text.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.6,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  _followers.length == 1
                                      ? 'student follows your updates'
                                      : 'students follow your updates',
                                  style: text.bodyMedium
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (_followers.length > 5)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: TextField(
                                controller: _searchController,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Search by name or country',
                                  prefixIcon:
                                      const Icon(Icons.search_rounded, size: 20),
                                  suffixIcon: _search.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18),
                                          tooltip: 'Clear',
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _search = '');
                                          },
                                        )
                                      : null,
                                  isDense: true,
                                ),
                                onChanged: (val) => setState(() => _search = val),
                              ),
                            ),
                          OrgSectionLabel(
                            _search.isEmpty ? 'Everyone' : 'Matching',
                            count: followers.length,
                          ),
                          if (followers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text('Nobody matches that search.',
                                  style: text.bodySmall),
                            )
                          else
                            OrgGroup(
                              children: [
                                for (final follower in followers)
                                  OrgRow(
                                    leading: UserAvatar(
                                      avatarUrl: follower.avatarUrl,
                                      initials: follower.initials,
                                      size: 44,
                                    ),
                                    title: follower.fullName,
                                    subtitle: [
                                      if (follower.country != null)
                                        countryLabel(follower.country),
                                      'followed ${formatRelative(follower.followedAt)}',
                                    ].join(' · '),
                                    trailing: IconButton(
                                      onPressed: () => _messageStudent(follower),
                                      icon: Icon(Icons.chat_bubble_outline_rounded,
                                          size: 20, color: colors.textPrimary),
                                      tooltip: 'Message ${follower.fullName}',
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
