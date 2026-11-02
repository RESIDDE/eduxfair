import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/passport.dart';
import '../providers/passport_provider.dart';

/// The passport wizard.
///
/// Four steps, ordered by what unlocks matching soonest: intent first (what
/// they want), then academics, then identity, then the optional extras. A
/// student who abandons after step one still has the three fields that matter
/// most for being discovered.
class PassportEditScreen extends StatefulWidget {
  const PassportEditScreen({super.key});

  @override
  State<PassportEditScreen> createState() => _PassportEditScreenState();
}

class _PassportEditScreenState extends State<PassportEditScreen> {
  final _pageController = PageController();
  int _step = 0;

  // Step 1 — intent
  List<String> _targetCountries = [];
  List<String> _targetLevels = [];
  List<String> _targetFields = [];
  String? _intake;

  // Step 2 — academics
  final _qualification = TextEditingController();
  final _grade = TextEditingController();
  String? _gradeScheme;
  String _englishTest = 'none';
  final _englishScore = TextEditingController();

  // Step 3 — identity
  DateTime? _dateOfBirth;
  String? _nationality;
  String? _currentCountry;

  // Step 4 — optional
  final _budgetMin = TextEditingController();
  final _budgetMax = TextEditingController();
  String _budgetCurrency = 'USD';
  final _bio = TextEditingController();

  bool _prefilled = false;

  static const _stepTitles = [
    'What are you looking for?',
    'Your academics',
    'About you',
    'Budget and bio',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<PassportProvider>();
      if (provider.passport == null || provider.fields.isEmpty) {
        await provider.load();
      }
      if (mounted) _prefill(provider.passport);
    });
  }

  void _prefill(Passport? p) {
    if (_prefilled || p == null) {
      setState(() => _prefilled = true);
      return;
    }
    setState(() {
      _targetCountries = [...p.targetCountries];
      _targetLevels = [...p.targetLevels];
      _targetFields = [...p.targetFields];
      _intake = p.intendedIntake;
      _qualification.text = p.highestQualification ?? '';
      _grade.text = p.gradeValue?.toString() ?? '';
      _gradeScheme = p.gradeScheme;
      _englishTest = p.englishTestName;
      _englishScore.text = p.englishScore?.toString() ?? '';
      _dateOfBirth = p.dateOfBirth;
      _nationality = p.nationality;
      _currentCountry = p.currentCountry;
      _budgetMin.text = formatAmountWithCommas(p.budgetMin);
      _budgetMax.text = formatAmountWithCommas(p.budgetMax);
      _budgetCurrency = p.budgetCurrency;
      _bio.text = p.bio ?? '';
      _prefilled = true;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _qualification.dispose();
    _grade.dispose();
    _englishScore.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// Validates only the step being left, so a student is never blocked by a
  /// field three screens away.
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        return AppValidators.validateTargetCountries(_targetCountries) ??
            (_targetLevels.isEmpty ? 'Choose at least one study level' : null) ??
            AppValidators.validateFieldSelection(_targetFields);
      case 1:
        if (_qualification.text.trim().isEmpty) {
          return 'Enter your highest qualification';
        }
        if (_gradeScheme == null) return 'Choose your grading scheme';
        final gradeError =
            AppValidators.validateGrade(_grade.text, _gradeScheme);
        if (gradeError != null) return gradeError;
        if (_englishTest != 'none') {
          return AppValidators.validateEnglishScore(
              _englishScore.text, _englishTest);
        }
        return null;
      case 2:
        return AppValidators.validateDateOfBirth(_dateOfBirth) ??
            (_nationality == null ? 'Choose your nationality' : null) ??
            (_currentCountry == null ? 'Choose where you live now' : null);
      case 3:
        final minError = AppValidators.validateBudget(_budgetMin.text);
        if (minError != null) return minError;
        final maxError = AppValidators.validateBudget(_budgetMax.text);
        if (maxError != null) return maxError;
        final min = double.tryParse(_budgetMin.text.trim());
        final max = double.tryParse(_budgetMax.text.trim());
        if (min != null && max != null && min > max) {
          return 'Your minimum cannot be higher than your maximum';
        }
        return null;
      default:
        return null;
    }
  }

  void _next() {
    final error = _validateStep(_step);
    if (error != null) {
      _toast(error, isError: true);
      return;
    }

    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _save();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step--);
    _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _save() async {
    final provider = context.read<PassportProvider>();

    // A brand-new passport has no row yet, so the id has to come from the
    // session rather than from the (absent) passport.
    final id = provider.passport?.profileId ??
        context.read<AuthProvider>().user?.id;
    if (id == null) {
      _toast('You are not signed in.', isError: true);
      return;
    }

    final updated = Passport(
      profileId: id,
      dateOfBirth: _dateOfBirth,
      nationality: _nationality,
      currentCountry: _currentCountry,
      highestQualification: _qualification.text.trim().isEmpty
          ? null
          : _qualification.text.trim(),
      gradeValue: double.tryParse(_grade.text.trim()),
      gradeScheme: _gradeScheme,
      englishTestName: _englishTest,
      englishScore: _englishTest == 'none'
          ? null
          : double.tryParse(_englishScore.text.trim()),
      targetCountries: _targetCountries,
      targetLevels: _targetLevels,
      targetFields: _targetFields,
      budgetMin: double.tryParse(_budgetMin.text.trim().replaceAll(',', '')),
      budgetMax: double.tryParse(_budgetMax.text.trim().replaceAll(',', '')),
      budgetCurrency: _budgetCurrency,
      intendedIntake: _intake,
      bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
    );

    final ok = await provider.save(updated);
    if (!mounted) return;

    if (ok) {
      final completeness = provider.completeness;
      _toast(provider.isMatchable
          ? 'Saved. Your passport is $completeness% complete and '
              'institutions can now find you.'
          : 'Saved. Your passport is $completeness% complete.');
      Navigator.of(context).pop();
    } else {
      _toast(provider.error ?? 'Could not save your passport.', isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? context.colors.error : null,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<PassportProvider>();
    final isLast = _step == _stepTitles.length - 1;

    if (!_prefilled) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _back,
        ),
        title: Text('Step ${_step + 1} of ${_stepTitles.length}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SmoothPageIndicator(
                    controller: _pageController,
                    count: _stepTitles.length,
                    effect: ExpandingDotsEffect(
                      dotHeight: 6,
                      dotWidth: 6,
                      expansionFactor: 4,
                      activeDotColor: colors.accent,
                      dotColor: colors.border,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(_stepTitles[_step], style: text.headlineMedium),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                // Driven by the buttons so each step is validated on the way
                // out; swiping would skip that.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _intentStep(provider),
                  _academicsStep(),
                  _identityStep(),
                  _extrasStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: provider.saving ? null : _next,
                child: provider.saving
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: context.colors.onAccent,
                        ),
                      )
                    : Text(isLast ? 'Save my passport' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: intent ────────────────────────────────────────────────────────

  Widget _intentStep(PassportProvider provider) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            'These three answers are what institutions match against, so they '
            'matter most.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 20),
          _MultiSelectField(
            label: 'Where do you want to study?',
            options: AppConstants.popularDestinations,
            selected: _targetCountries,
            onChanged: (v) => setState(() => _targetCountries = v),
          ),
          const SizedBox(height: 20),
          _MultiSelectField(
            label: 'What level?',
            options: AppConstants.studyLevels,
            selected: _targetLevels,
            onChanged: (v) => setState(() => _targetLevels = v),
          ),
          const SizedBox(height: 20),
          _MultiSelectField(
            label: 'Which field of study?',
            // From the database vocabulary, not free text: a typed subject
            // would never match any program.
            options: {for (final f in provider.fields) f.slug: f.label},
            selected: _targetFields,
            onChanged: (v) => setState(() => _targetFields = v),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _intake,
            decoration: const InputDecoration(
              labelText: 'When do you want to start?',
              prefixIcon: Icon(Icons.calendar_today_rounded, size: 20),
            ),
            items: AppConstants.intakes
                .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                .toList(),
            onChanged: (v) => setState(() => _intake = v),
          ),
        ],
      );

  // ── Step 2: academics ─────────────────────────────────────────────────────

  Widget _academicsStep() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          CustomTextField(
            controller: _qualification,
            label: 'Highest qualification',
            hint: 'e.g. WASSCE, BSc Accounting, A-Levels',
            prefixIcon: Icons.school_outlined,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _gradeScheme,
            decoration: const InputDecoration(
              labelText: 'How are your grades measured?',
              prefixIcon: Icon(Icons.straighten_rounded, size: 20),
            ),
            items: AppConstants.gradingSchemes.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _gradeScheme = v),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _grade,
            label: 'Your grade',
            hint: _gradeHint,
            prefixIcon: Icons.grade_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // Says plainly what the conversion is and is not, because a
            // student comparing their WAEC grade to a UK requirement deserves
            // to know this is an aid, not a credential evaluation.
            'We convert grades across systems so you can be compared fairly. '
            'The institution always makes the final assessment.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _englishTest,
            decoration: const InputDecoration(
              labelText: 'English test',
              prefixIcon: Icon(Icons.translate_rounded, size: 20),
            ),
            items: AppConstants.englishTests.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _englishTest = v ?? 'none'),
          ),
          if (_englishTest != 'none') ...[
            const SizedBox(height: 20),
            CustomTextField(
              controller: _englishScore,
              label: 'Your score',
              hint: _englishHint,
              prefixIcon: Icons.numbers_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ],
        ],
      );

  String get _gradeHint => switch (_gradeScheme) {
        'percentage' => 'e.g. 78',
        'gpa_4' => 'e.g. 3.4',
        'gpa_5' => 'e.g. 4.2',
        'waec' => '1 for A1, 6 for C6',
        'uk_class' => '1, 2.1, 2.2 or 3',
        'ib' => 'e.g. 34',
        'a_level' => '6 for A*, 5 for A',
        _ => 'Choose a scheme first',
      };

  String get _englishHint => switch (_englishTest) {
        'ielts' => 'e.g. 6.5',
        'toefl' => 'e.g. 90',
        'duolingo' => 'e.g. 120',
        'pte' => 'e.g. 62',
        'waec_english' => '1 for A1, 6 for C6',
        _ => '',
      };

  // ── Step 3: identity ──────────────────────────────────────────────────────

  Widget _identityStep() {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _dateOfBirth ?? DateTime(now.year - 20),
              firstDate: DateTime(now.year - 80),
              lastDate: DateTime(now.year - 14),
              helpText: 'Your date of birth',
            );
            if (picked != null) setState(() => _dateOfBirth = picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date of birth',
              prefixIcon: Icon(Icons.cake_outlined, size: 20),
            ),
            child: Text(
              _dateOfBirth == null
                  ? 'Select a date'
                  : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
              style: text.bodyMedium?.copyWith(
                color: _dateOfBirth == null
                    ? colors.textLight
                    : colors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: _nationality,
          decoration: const InputDecoration(
            labelText: 'Nationality',
            prefixIcon: Icon(Icons.flag_outlined, size: 20),
          ),
          items: AppConstants.homeCountries.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _nationality = v),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: _currentCountry,
          decoration: const InputDecoration(
            labelText: 'Where do you live now?',
            prefixIcon: Icon(Icons.home_outlined, size: 20),
          ),
          items: AppConstants.homeCountries.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _currentCountry = v),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.infoLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Institutions see only your country, study level, field and '
                  'grade band until you choose to share your passport. Your '
                  'name and documents stay private.',
                  style: text.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 4: extras ────────────────────────────────────────────────────────

  Widget _extrasStep() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            'Optional, but a budget helps us rule out programs you could not '
            'take up anyway.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _budgetCurrency,
            decoration: const InputDecoration(
              labelText: 'Currency',
              prefixIcon: Icon(Icons.payments_outlined, size: 20),
            ),
            items: const ['USD', 'GBP', 'EUR', 'CAD', 'NGN']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _budgetCurrency = v ?? 'USD'),
          ),
          const SizedBox(height: 8),
          Text(
            // Explains the "not compared" reason code a student may see on a
            // match, rather than leaving it mysterious.
            'Budgets are compared only against tuition in the same currency — '
            'we do not guess exchange rates.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _budgetMin,
                  label: 'From',
                  hint: '5,000',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: _budgetMax,
                  label: 'Up to',
                  hint: '30,000',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _bio,
            label: 'A short note for institutions',
            hint: 'What you want to study and why. Two or three sentences.',
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      );
}

/// A labelled chip multi-select.
///
/// Chips rather than a dropdown because every one of these fields is genuinely
/// multi-choice and a student needs to see all their selections at once.
class _MultiSelectField extends StatelessWidget {
  final String label;
  final Map<String, String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _MultiSelectField({
    required this.label,
    required this.options,
    required this.selected,
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
        if (options.isEmpty)
          Text('Loading options…', style: text.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.entries.map((entry) {
              final isSelected = selected.contains(entry.key);
              return FilterChip(
                label: Text(entry.value),
                selected: isSelected,
                showCheckmark: false,
                onSelected: (_) {
                  final next = [...selected];
                  isSelected ? next.remove(entry.key) : next.add(entry.key);
                  onChanged(next);
                },
                backgroundColor: colors.surface,
                selectedColor: colors.accent,
                side: BorderSide(
                  color: isSelected ? colors.accent : colors.border,
                ),
                labelStyle: text.bodyMedium?.copyWith(
                  color: isSelected ? context.colors.onAccent : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
