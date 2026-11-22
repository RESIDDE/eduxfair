import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../widgets/org_ui.dart';
import '../models/org_fair.dart';
import '../providers/institution_provider.dart';

/// Fairs, booth code management, and student lead capture for admissions staff.
///
/// Staff scan or enter student 8-character Fair Passport codes at their booth to
/// record visits and immediately gain passport access.
class OrgFairsScreen extends StatefulWidget {
  const OrgFairsScreen({super.key});

  @override
  State<OrgFairsScreen> createState() => _OrgFairsScreenState();
}

class _OrgFairsScreenState extends State<OrgFairsScreen> {
  final _service = SupabaseService.instance;

  bool _loading = true;
  String? _error;
  List<OrgExhibitor> _exhibitors = [];
  List<OrgBoothLead> _leads = [];
  List<Map<String, dynamic>> _programs = [];

  String? _selectedExhibitorId;
  String _leadFilter = 'all'; // 'all', 'follow_up', 'scholarship', 'high'
  bool _busy = false;

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
      final results = await Future.wait([
        _service.client
            .from('fair_exhibitors')
            .select('id, booth_code, booth_label, package, fair_id, fairs!inner(*)')
            .eq('institution_id', institutionId)
            .order('created_at', ascending: false),
        _service.client
            .from('booth_visits')
            .select(
              'id, interest_level, follow_up_requested, scholarship_discussed, '
              'program_interest, note, created_at, exhibitor_id, profile_id, '
              'student:profiles!profile_id(id, full_name, country), programs(id, name)',
            )
            .order('created_at', ascending: false)
            .limit(300),
        _service.client
            .from('programs')
            .select('id, name')
            .eq('institution_id', institutionId)
            .eq('is_active', true)
            .order('name'),
      ]);

      if (!mounted) return;
      final exhibitors = (results[0] as List)
          .map((r) => OrgExhibitor.fromMap((r as Map).cast<String, dynamic>()))
          .toList();

      final leads = (results[1] as List)
          .map((r) => OrgBoothLead.fromMap((r as Map).cast<String, dynamic>()))
          .toList();

      final programs = (results[2] as List).cast<Map<String, dynamic>>();

      setState(() {
        _exhibitors = exhibitors;
        _leads = leads;
        _programs = programs;
        if (_selectedExhibitorId == null && exhibitors.isNotEmpty) {
          _selectedExhibitorId = exhibitors.first.id;
        }
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

  OrgExhibitor? get _currentExhibitor {
    if (_exhibitors.isEmpty) return null;
    return _exhibitors.firstWhere(
      (e) => e.id == _selectedExhibitorId,
      orElse: () => _exhibitors.first,
    );
  }

  List<OrgBoothLead> get _filteredLeads {
    final exhibitor = _currentExhibitor;
    if (exhibitor == null) return const [];

    final list = _leads.where((l) => l.exhibitorId == exhibitor.id).toList();

    switch (_leadFilter) {
      case 'follow_up':
        return list.where((l) => l.followUpRequested).toList();
      case 'scholarship':
        return list.where((l) => l.scholarshipDiscussed).toList();
      case 'high':
        return list.where((l) => l.interestLevel == 'high').toList();
      default:
        return list;
    }
  }

  Future<void> _recordVisit(OrgExhibitor exhibitor) async {
    final passCodeController = TextEditingController();
    final noteController = TextEditingController();
    String? selectedProgramId;
    String interestLevel = 'medium';
    bool followUp = false;
    bool scholarship = false;
    String? formError;
    String? formSuccess;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
              child: SingleChildScrollView(
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
                          child: Icon(Icons.qr_code_scanner_rounded,
                              color: colors.accent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Record booth visit', style: text.titleLarge),
                              Text(
                                'Booth ${exhibitor.boothCode} · ${exhibitor.fair?.name ?? 'Fair'}',
                                style: text.bodySmall?.copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Type the 8-character pass code from the student’s Fair Passport. Connecting automatically grants passport access.',
                      style: text.bodySmall?.copyWith(color: colors.textSecondary, height: 1.45),
                    ),

                    if (formError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.errorLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          formError!,
                          style: text.bodySmall?.copyWith(color: colors.error, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],

                    if (formSuccess != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.successLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          formSuccess!,
                          style: text.bodySmall?.copyWith(color: colors.success, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: passCodeController,
                      label: 'Student Pass Code',
                      hint: 'e.g. SQ53W4WS',
                      textCapitalization: TextCapitalization.characters,
                      autofocus: true,
                    ),

                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedProgramId,
                      decoration: InputDecoration(
                        labelText: 'Program of interest (optional)',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('General enquiry'),
                        ),
                        ..._programs.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p['id'] as String,
                            child: Text(p['name'] as String? ?? 'Program',
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (val) => setSheetState(() => selectedProgramId = val),
                    ),

                    const SizedBox(height: 16),
                    Text('Interest level', style: text.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: ['low', 'medium', 'high'].map((level) {
                        final isSel = interestLevel == level;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(level[0].toUpperCase() + level.substring(1)),
                            selected: isSel,
                            onSelected: (_) => setSheetState(() => interestLevel = level),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: followUp,
                      title: const Text('Follow-up requested'),
                      subtitle: const Text('Student wants admissions callback or materials'),
                      onChanged: (val) => setSheetState(() => followUp = val ?? false),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: scholarship,
                      title: const Text('Scholarship discussed'),
                      subtitle: const Text('Discussed financial aid / tuition waiver'),
                      onChanged: (val) => setSheetState(() => scholarship = val ?? false),
                    ),

                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: noteController,
                      label: 'Booth note (optional)',
                      hint: 'Notes on student background, requirements discussed...',
                      maxLines: 2,
                    ),

                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Done'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final code = passCodeController.text.replaceAll(' ', '').trim();
                                    if (code.isEmpty) {
                                      setSheetState(() => formError = 'Please enter a pass code.');
                                      return;
                                    }

                                    setSheetState(() {
                                      _busy = true;
                                      formError = null;
                                      formSuccess = null;
                                    });

                                    try {
                                      await _service.client.rpc('record_booth_visit', params: {
                                        'p_pass_code': code,
                                        'p_booth_code': exhibitor.boothCode,
                                        'p_program_id': selectedProgramId,
                                        'p_interest_level': interestLevel,
                                        'p_follow_up_requested': followUp,
                                        'p_scholarship_discussed': scholarship,
                                        'p_note': noteController.text.trim().isEmpty
                                            ? null
                                            : noteController.text.trim(),
                                      });

                                      setSheetState(() {
                                        formSuccess = 'Connected! Passport shared with your team.';
                                        passCodeController.clear();
                                        noteController.clear();
                                        _busy = false;
                                      });

                                      _load();
                                    } catch (e) {
                                      setSheetState(() {
                                        formError = SupabaseService.describeError(e);
                                        _busy = false;
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Record visit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(), title: const Text('Fairs and booths')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(), title: const Text('Fairs and booths')),
        body: ErrorState(message: _error!, onRetry: _load),
      );
    }

    if (_exhibitors.isEmpty) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(), title: const Text('Fairs and booths')),
        body: const EmptyState(
          icon: Icons.qr_code_2_rounded,
          title: 'Not exhibiting yet',
          message: 'Eduxfair assigns your booth code when you register for an Education Fair. Once assigned, you can scan and capture student leads from here.',
        ),
      );
    }

    final exhibitor = _currentExhibitor!;
    final leads = _filteredLeads;
    final allBoothVisits = _leads.where((l) => l.exhibitorId == exhibitor.id).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Fairs and booths'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // If multiple fairs, show picker
            if (_exhibitors.length > 1) ...[
              // Fairs as pills: you are at one at a time, and switching is a
              // tap rather than a dropdown.
              Padding(
                padding: EdgeInsets.zero,
                child: OrgFilterBar<String>(
                  padding: EdgeInsets.zero,
                  selected: exhibitor.id,
                  onSelected: (v) => setState(() => _selectedExhibitorId = v),
                  options: [
                    for (final e in _exhibitors) (e.id, e.fair?.name ?? 'Fair'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Booth Hero Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: colors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          exhibitor.package.toUpperCase().replaceAll('_', ' '),
                          style: text.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (exhibitor.fair != null)
                        Text(
                          formatDate(exhibitor.fair!.startsAt),
                          style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    exhibitor.fair?.name ?? 'Education Fair',
                    style: text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  if (exhibitor.fair?.venue != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${exhibitor.fair!.venue}${exhibitor.fair!.city != null ? ', ${exhibitor.fair!.city}' : ''}',
                      style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Booth Code display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BOOTH CODE',
                              style: text.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              exhibitor.boothCode,
                              style: text.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: exhibitor.boothCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Booth code copied to clipboard.')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, color: Colors.white),
                          tooltip: 'Copy booth code',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: colors.primary,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _recordVisit(exhibitor),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scan / Record student visit', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Statistics — plain numbers in the text colour, like Home.
            GridView.count(
              crossAxisCount: 2,
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.3,
              children: [
                _StatCard(title: 'Students met', value: '${allBoothVisits.length}'),
                _StatCard(
                    title: 'Want a follow-up',
                    value: '${allBoothVisits.where((v) => v.followUpRequested).length}'),
                _StatCard(
                    title: 'Scholarship questions',
                    value: '${allBoothVisits.where((v) => v.scholarshipDiscussed).length}'),
                _StatCard(
                    title: 'High interest',
                    value: '${allBoothVisits.where((v) => v.interestLevel == 'high').length}'),
              ],
            ),

            OrgSectionLabel('Students you met',
                count: leads.length,
                padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
            OrgFilterBar<String>(
              padding: EdgeInsets.zero,
              selected: _leadFilter,
              onSelected: (v) => setState(() => _leadFilter = v),
              options: const [
                ('all', 'Everyone'),
                ('follow_up', 'Want a follow-up'),
                ('high', 'High interest'),
              ],
            ),
            const SizedBox(height: 12),

            if (leads.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    'Nobody here yet.',
                    style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                  ),
                ),
              )
            else
              OrgGroup(
                margin: EdgeInsets.zero,
                children: [for (final lead in leads) _LeadRow(lead: lead)],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;

  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          Text(
            title,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  final OrgBoothLead lead;

  const _LeadRow({required this.lead});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initials = lead.studentName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final programme = lead.programName ?? lead.programInterest;
    final note = (lead.note ?? '').trim();

    return OrgRow(
      leading: UserAvatar(initials: initials.isEmpty ? 'S' : initials, size: 44),
      title: lead.studentName,
      meta: formatRelative(lead.createdAt),
      subtitle: [
        if (lead.studentCountry != null) countryLabel(lead.studentCountry),
        if (programme != null) programme,
        if (note.isNotEmpty) '“$note”',
      ].join(' · '),
      tags: [
        if (lead.interestLevel == 'high')
          OrgTag('High interest', tone: colors.success),
        if (lead.interestLevel == 'medium') const OrgTag('Some interest'),
        if (lead.followUpRequested) const OrgTag('Wants a follow-up'),
        if (lead.scholarshipDiscussed) const OrgTag('Scholarships'),
      ],
    );
  }
}
