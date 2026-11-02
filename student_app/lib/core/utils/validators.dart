import '../constants/app_constants.dart';

/// Form validators.
///
/// Adapted from consult_client, minus the automotive ones (VIN, vehicle year)
/// and plus the ones this domain needs: grades in seven different schemes and
/// English scores on four different scales.
class AppValidators {
  AppValidators._();

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    // Deliberately permissive: the only authoritative test of an address is
    // whether mail to it arrives, and a strict pattern rejects valid addresses.
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 7 || digitsOnly.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'This field is required';
    if (value.trim().length < 2) return 'Must be at least 2 characters';
    return null;
  }

  static String? validateRequired(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  /// Validates a grade against the scheme it was entered in.
  ///
  /// Each scheme has a different range, and two of them run backwards (WAEC
  /// where A1 = 1, and UK classifications where a First = 1), so a single
  /// numeric range check would accept nonsense.
  static String? validateGrade(String? value, String? scheme) {
    if (value == null || value.trim().isEmpty) return 'Enter your grade';
    if (scheme == null) return 'Choose a grading scheme first';

    final grade = double.tryParse(value.trim());
    if (grade == null) return 'Enter a number';

    final (min, max, hint) = switch (scheme) {
      'percentage' => (0.0, 100.0, 'between 0 and 100'),
      'gpa_4' => (0.0, 4.0, 'between 0 and 4.0'),
      'gpa_5' => (0.0, 5.0, 'between 0 and 5.0'),
      'ib' => (0.0, 45.0, 'between 0 and 45'),
      'a_level' => (1.0, 6.0, 'between 1 (E) and 6 (A*)'),
      'waec' => (1.0, 9.0, 'between 1 (A1) and 9 (F9)'),
      'uk_class' => (1.0, 3.0, '1, 2.1, 2.2 or 3'),
      _ => (0.0, 100.0, 'a valid number'),
    };

    if (grade < min || grade > max) return 'Enter $hint';

    if (scheme == 'waec' && grade != grade.roundToDouble()) {
      return 'WAEC grades are whole numbers (1 for A1, 6 for C6)';
    }
    if (scheme == 'uk_class' && ![1.0, 2.1, 2.2, 3.0].contains(grade)) {
      return 'Enter 1, 2.1, 2.2 or 3';
    }

    return null;
  }

  /// Validates an English test score against the test's own scale.
  static String? validateEnglishScore(String? value, String test) {
    if (test == 'none') return null;
    if (value == null || value.trim().isEmpty) return 'Enter your score';

    final score = double.tryParse(value.trim());
    if (score == null) return 'Enter a number';

    final (min, max, label) = switch (test) {
      'ielts' => (0.0, 9.0, 'IELTS band between 0 and 9'),
      'toefl' => (0.0, 120.0, 'TOEFL score between 0 and 120'),
      'duolingo' => (10.0, 160.0, 'Duolingo score between 10 and 160'),
      'pte' => (10.0, 90.0, 'PTE score between 10 and 90'),
      'waec_english' => (1.0, 9.0, 'WAEC grade between 1 (A1) and 9 (F9)'),
      _ => (0.0, 1000.0, 'valid score'),
    };

    if (score < min || score > max) return 'Enter a $label';

    if (test == 'ielts' && (score * 2) != (score * 2).roundToDouble()) {
      return 'IELTS bands go in halves, e.g. 6.5';
    }

    return null;
  }

  /// Validates a budget figure. Optional, so an empty value is allowed.
  static String? validateBudget(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final amount = double.tryParse(value.trim().replaceAll(',', ''));
    if (amount == null) return 'Enter a number';
    if (amount < 0) return 'Enter a positive amount';
    if (amount > 1000000) return 'That looks too high — check the figure';
    return null;
  }

  /// A selection from the controlled field-of-study vocabulary.
  ///
  /// Free text here would silently break matching, because the database
  /// compares these against `programs.field_of_study`.
  static String? validateFieldSelection(List<String>? selected) {
    if (selected == null || selected.isEmpty) {
      return 'Choose at least one field of study';
    }
    return null;
  }

  static String? validateTargetCountries(List<String>? selected) {
    if (selected == null || selected.isEmpty) {
      return 'Choose at least one destination';
    }
    return null;
  }

  /// A plausible date of birth for a prospective international student.
  static String? validateDateOfBirth(DateTime? value) {
    if (value == null) return 'Select your date of birth';
    final age = DateTime.now().difference(value).inDays / 365.25;
    if (age < 14) return 'You must be at least 14 to register';
    if (age > 80) return 'Please check that date';
    return null;
  }

  /// A 6-digit email verification code.
  static String? validateOtp(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter the code';
    if (value.trim().length != 6) return 'The code is 6 digits';
    if (int.tryParse(value.trim()) == null) return 'Digits only';
    return null;
  }

  /// A Fair Passport code. The alphabet deliberately excludes I, O, 0 and 1, so
  /// a code misread at a busy desk fails here rather than silently resolving to
  /// someone else.
  static String? validatePassCode(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter the pass code';
    final code = value.trim().toUpperCase().replaceAll(' ', '');
    if (code.length != 8) return 'Pass codes are 8 characters';
    if (!RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$').hasMatch(code)) {
      return 'That is not a valid pass code';
    }
    return null;
  }

  /// Checks a study level against the `study_level` enum.
  static String? validateStudyLevel(String? value) {
    if (value == null || value.isEmpty) return 'Choose a study level';
    if (!AppConstants.studyLevels.containsKey(value)) return 'Invalid level';
    return null;
  }
}
