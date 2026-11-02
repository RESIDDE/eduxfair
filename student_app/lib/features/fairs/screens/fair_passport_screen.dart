import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/fair.dart';
import '../providers/fairs_provider.dart';

/// The Fair Passport: the QR a booth scans to connect.
///
/// The scan itself is authorized by the staff member's booth membership, not
/// by knowing this code, and `record_booth_visit()` checks both. So showing
/// the code on screen is safe, and printing it is how a student recovers when
/// their battery dies.
class FairPassportScreen extends StatefulWidget {
  const FairPassportScreen({super.key});

  @override
  State<FairPassportScreen> createState() => _FairPassportScreenState();
}

class _FairPassportScreenState extends State<FairPassportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FairsProvider>().load();
    });
  }

  Future<void> _register(Fair fair) async {
    final provider = context.read<FairsProvider>();
    final ok = await provider.register(fair.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'You are registered. Your Fair Passport is ready.'
            : provider.error ?? 'Could not register.'),
        backgroundColor: ok ? null : context.colors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<FairsProvider>();
    final registration = provider.currentRegistration;

    return Scaffold(
      appBar: AppBar(title: const Text('Fair Passport')),
      body: provider.loading && provider.registrations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (registration != null) ...[
                    _PassCard(registration: registration),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.infoLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lightbulb_outline_rounded,
                                  size: 18, color: colors.accent),
                              const SizedBox(width: 8),
                              Text(
                                'How it works',
                                style: text.titleSmall?.copyWith(
                                  color: colors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...const [
                            'Walk up to any booth and show this code.',
                            'They scan it — no forms, no repeating yourself.',
                            'Connecting lets that institution see your '
                                'passport. You can revoke it afterwards.',
                            'At the end you get a report of everyone you met.',
                          ].map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.circle,
                                      size: 5, color: colors.accent),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      line,
                                      style: text.bodySmall
                                          ?.copyWith(height: 1.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (registration.fair != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => context.push(
                          '${AppConstants.routeFairReport}/${registration.fairId}',
                        ),
                        icon: const Icon(Icons.assessment_outlined, size: 18),
                        label: const Text('My fair report'),
                      ),
                    ],
                  ] else if (provider.upcomingFairs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: EmptyState(
                        icon: Icons.event_busy_outlined,
                        title: 'No fairs scheduled',
                        message: 'When Eduxfair announces the next education '
                            'fair, you will be able to register here and get '
                            'your Fair Passport.',
                      ),
                    )
                  else ...[
                    Text('Upcoming fairs', style: text.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Register to get a QR pass you can show at every booth.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    ...provider.upcomingFairs.map(
                      (fair) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FairTile(
                          fair: fair,
                          registered: provider.isRegistered(fair.id),
                          busy: provider.busy,
                          onRegister: () => _register(fair),
                        ),
                      ),
                    ),
                  ],

                  if (provider.visits.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text('Booths you have connected with',
                        style: text.titleLarge),
                    const SizedBox(height: 12),
                    ...provider.visits.map(
                      (visit) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _VisitTile(visit: visit),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _PassCard extends StatelessWidget {
  final FairRegistration registration;

  const _PassCard({required this.registration});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final fair = registration.fair;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: colors.primaryGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Text(
            fair?.name ?? 'Eduxfair',
            style: text.titleMedium?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          if (fair != null) ...[
            const SizedBox(height: 4),
            Text(
              '${fair.location} · ${_formatDate(fair.startsAt)}',
              style: text.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: QrImageView(
              data: registration.passCode,
              version: QrVersions.auto,
              size: 196,
              // Fixed white background: a QR rendered on a themed surface can
              // fail to scan in low light at a busy venue.
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0F1419),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0F1419),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'PASS CODE',
            style: text.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          // Also readable aloud: the alphabet excludes I, O, 0 and 1 so a code
          // dictated at a noisy desk cannot resolve to someone else.
          Text(
            registration.displayCode,
            style: text.headlineSmall?.copyWith(
              color: Colors.white,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (registration.isCheckedIn) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 15, color: colors.success),
                const SizedBox(width: 6),
                Text(
                  'Checked in',
                  style: text.labelMedium?.copyWith(color: colors.success),
                ),
              ],
            ),
          ],
        ],
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

class _FairTile extends StatelessWidget {
  final Fair fair;
  final bool registered;
  final bool busy;
  final VoidCallback onRegister;

  const _FairTile({
    required this.fair,
    required this.registered,
    required this.busy,
    required this.onRegister,
  });

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
          Text(fair.name, style: text.titleMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 14, color: colors.textLight),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  fair.venue == null
                      ? fair.location
                      : '${fair.venue}, ${fair.location}',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 13, color: colors.textLight),
              const SizedBox(width: 6),
              Text(_dateRange(fair), style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: registered
                ? OutlinedButton(
                    onPressed: null,
                    child: const Text('Registered'),
                  )
                : ElevatedButton(
                    onPressed: busy ? null : onRegister,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                    child: const Text('Register'),
                  ),
          ),
        ],
      ),
    );
  }

  static String _dateRange(Fair fair) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final start = fair.startsAt;
    final end = fair.endsAt;
    if (start.month == end.month && start.day == end.day) {
      return '${start.day} ${months[start.month - 1]} ${start.year}';
    }
    return '${start.day}–${end.day} ${months[end.month - 1]} ${end.year}';
  }
}

class _VisitTile extends StatelessWidget {
  final BoothVisit visit;

  const _VisitTile({required this.visit});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          InstitutionAvatar(
            logoUrl: visit.institutionLogoUrl,
            initials: visit.institutionName.isEmpty
                ? '?'
                : visit.institutionName[0].toUpperCase(),
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.institutionName,
                    style: text.titleMedium, overflow: TextOverflow.ellipsis),
                if (visit.programInterest != null)
                  Text(visit.programInterest!, style: text.bodySmall),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (visit.followUpRequested)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.reply_rounded,
                            size: 13, color: colors.accent),
                      ),
                    if (visit.scholarshipDiscussed)
                      Icon(Icons.savings_rounded,
                          size: 13, color: colors.warning),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
