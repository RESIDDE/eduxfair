import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/surface.dart';
import '../../discover/models/program.dart';
import '../providers/institution_provider.dart';

/// The courses an institution offers.
///
/// This is the screen the rest of the product hangs off. `match_scores` is
/// computed from a student's passport against these rows, so an institution
/// with no programs is invisible to matching and its Matched students screen is
/// empty by arithmetic rather than by fault. That is worth saying on the empty
/// state, because "no matches yet" and "nothing to match against" look
/// identical from the outside.
class OrgProgramsScreen extends StatefulWidget {
  const OrgProgramsScreen({super.key});

  @override
  State<OrgProgramsScreen> createState() => _OrgProgramsScreenState();
}

class _OrgProgramsScreenState extends State<OrgProgramsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<InstitutionProvider>().loadPrograms());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final text = Theme.of(context).textTheme;
    final institutions = context.watch<InstitutionProvider>();
    final programs = institutions.programs;

    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add a program'),
      ),
      body: RefreshIndicator(
        onRefresh: institutions.loadPrograms,
        child: institutions.loadingPrograms && programs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : programs.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const SizedBox(height: 32),
                      const EmptyState(
                        icon: Icons.school_outlined,
                        title: 'Add what you teach',
                        message:
                            'Matching works off your programs. Until there is '
                            'at least one here, students cannot be matched to '
                            'you and your Matched students screen stays empty.',
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Tuition, intakes and entry requirements are all '
                          'optional — a name, level and subject is enough to '
                          'start matching.',
                          textAlign: TextAlign.center,
                          style: text.bodySmall
                              ?.copyWith(color: colors.textLight, height: 1.45),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: programs.length,
                    itemBuilder: (_, i) => _ProgramCard(
                      program: programs[i],
                      onEdit: () => _edit(context, programs[i]),
                    ),
                  ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, [Program? program]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProgramSheet(program: program),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final Program program;
  final VoidCallback onEdit;

  const _ProgramCard({required this.program, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final text = Theme.of(context).textTheme;
    final institutions = context.read<InstitutionProvider>();
    final fieldLabel =
        institutions.fieldLabels[program.fieldOfStudy] ?? program.fieldOfStudy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    program.name,
                    style: text.titleMedium?.copyWith(
                      color: program.isActive ? null : colors.textLight,
                    ),
                  ),
                ),
                if (!program.isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Retired',
                        style: text.labelSmall
                            ?.copyWith(color: colors.textSecondary)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${AppConstants.studyLevels[program.level] ?? program.level} · '
              '$fieldLabel',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(label: program.tuitionDisplay),
                _Chip(label: program.durationDisplay),
                if (program.intakes.isNotEmpty)
                  _Chip(label: program.intakes.join(', ')),
                if (program.scholarshipAvailable)
                  _Chip(label: 'Scholarship', accent: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: institutions.saving
                      ? null
                      : () => institutions.setProgramActive(
                          program.id, !program.isActive),
                  child: Text(program.isActive ? 'Retire' : 'Bring back'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool accent;
  const _Chip({required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? colors.successLight : colors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: accent ? colors.success : colors.textSecondary,
              fontWeight: accent ? FontWeight.w600 : null,
            ),
      ),
    );
  }
}

class _ProgramSheet extends StatefulWidget {
  final Program? program;
  const _ProgramSheet({this.program});

  @override
  State<_ProgramSheet> createState() => _ProgramSheetState();
}

class _ProgramSheetState extends State<_ProgramSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _tuitionMin;
  late final TextEditingController _tuitionMax;
  late final TextEditingController _duration;
  late final TextEditingController _intakes;
  late final TextEditingController _minGrade;
  late final TextEditingController _minEnglish;

  String? _level;
  String? _field;
  String? _gradeScheme;
  bool _scholarship = false;

  bool get _isNew => widget.program == null;

  @override
  void initState() {
    super.initState();
    final p = widget.program;
    _name = TextEditingController(text: p?.name ?? '');
    _tuitionMin = TextEditingController(text: formatAmountWithCommas(p?.tuitionMin));
    _tuitionMax = TextEditingController(text: formatAmountWithCommas(p?.tuitionMax));
    _duration = TextEditingController(text: p?.durationMonths?.toString() ?? '');
    _intakes = TextEditingController(text: p?.intakes.join(', ') ?? '');
    _minGrade = TextEditingController(text: p?.minGradeValue?.toString() ?? '');
    _minEnglish = TextEditingController(text: p?.minEnglishBand?.toString() ?? '');
    _level = p?.level;
    _field = p?.fieldOfStudy;
    _gradeScheme = p?.minGradeScheme;
    _scholarship = p?.scholarshipAvailable ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _name, _tuitionMin, _tuitionMax, _duration, _intakes, _minGrade, _minEnglish,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim().replaceAll(',', ''));

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final grade = _num(_minGrade);
    final institutions = context.read<InstitutionProvider>();

    final ok = await institutions.saveProgram(
      {
        'name': _name.text.trim(),
        'level': _level,
        'field_of_study': _field,
        'tuition_min': _num(_tuitionMin),
        'tuition_max': _num(_tuitionMax),
        'duration_months': int.tryParse(_duration.text.trim()),
        'intakes': _intakes.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'min_grade_value': grade,
        // programs_min_grade_needs_scheme requires both or neither, so the
        // scheme follows the value rather than being sent on its own.
        'min_grade_scheme': grade == null ? null : _gradeScheme,
        'min_english_band': _num(_minEnglish),
        'scholarship_available': _scholarship,
      },
      programId: widget.program?.id,
    );

    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final text = Theme.of(context).textTheme;
    final institutions = context.watch<InstitutionProvider>();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isNew ? 'Add a program' : 'Edit program',
                  style: text.titleLarge),
              const SizedBox(height: 18),

              CustomTextField(
                controller: _name,
                label: 'Program name',
                hint: 'BSc Computer Science',
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Give it a full name'
                    : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _level,
                decoration: const InputDecoration(labelText: 'Level'),
                items: AppConstants.studyLevels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _level = v),
                validator: (v) => v == null ? 'Choose a level' : null,
              ),
              const SizedBox(height: 16),

              // Loaded from fields_of_study, never typed. A subject that is not
              // in the vocabulary makes the program silently unmatchable.
              DropdownButtonFormField<String>(
                initialValue: _field,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: institutions.fieldsOfStudy
                    .map((f) => DropdownMenuItem(
                        value: f.slug,
                        child: Text(f.label, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _field = v),
                validator: (v) => v == null ? 'Choose a subject' : null,
              ),
              const SizedBox(height: 6),
              Text(
                'Students are matched on this, so pick the closest one rather '
                'than the most precise.',
                style: text.bodySmall?.copyWith(color: colors.textLight),
              ),
              const SizedBox(height: 18),

              Text('Tuition a year', style: text.labelLarge?.copyWith(
                  color: colors.textPrimary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      controller: _tuitionMin,
                      label: 'From',
                      hint: '15,000',
                      keyboardType: TextInputType.number,
                      inputFormatters: const [ThousandsSeparatorInputFormatter()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomTextField(
                      controller: _tuitionMax,
                      label: 'To',
                      hint: '25,000',
                      keyboardType: TextInputType.number,
                      inputFormatters: const [ThousandsSeparatorInputFormatter()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              CustomTextField(
                controller: _duration,
                label: 'Length in months',
                hint: '36',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),

              CustomTextField(
                controller: _intakes,
                label: 'Intakes',
                hint: 'Fall 2026, Winter 2027',
              ),
              const SizedBox(height: 6),
              Text('Separate them with commas.',
                  style: text.bodySmall?.copyWith(color: colors.textLight)),
              const SizedBox(height: 18),

              Text('Entry requirements', style: text.labelLarge?.copyWith(
                  color: colors.textPrimary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Optional. A student below these still sees you — they just '
                'score lower.',
                style: text.bodySmall?.copyWith(color: colors.textLight),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomTextField(
                      controller: _minGrade,
                      label: 'Minimum grade',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gradeScheme,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Scheme'),
                      items: AppConstants.gradingSchemes.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key,
                              child:
                                  Text(e.value, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _gradeScheme = v),
                      validator: (v) =>
                          (_minGrade.text.trim().isNotEmpty && v == null)
                              ? 'Which scheme?'
                              : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _minEnglish,
                label: 'Minimum English (IELTS equivalent)',
                hint: '6.5',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _scholarship,
                onChanged: (v) => setState(() => _scholarship = v),
                title: const Text('Scholarships available'),
                subtitle: Text(
                  'Students filtering for funding will see this.',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),

              if (institutions.error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(institutions.error!,
                      style: text.bodySmall?.copyWith(color: colors.error)),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  label: _isNew ? 'Add program' : 'Save changes',
                  isLoading: institutions.saving,
                  onPressed: _save,
                ),
              ),
              if (!_isNew) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: institutions.saving
                      ? null
                      : () async {
                          final ok = await institutions
                              .deleteProgram(widget.program!.id);
                          if (ok && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  child: Text('Delete',
                      style: TextStyle(color: colors.error)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
