// Unit tests for the domain logic that lives in Dart.
//
// The scoring and grade normalization that matter most live in Postgres and are
// covered by supabase/tests — these cover what the app itself decides: how a
// grade is displayed back to a student, what the passport reports as missing,
// which actions an application offers, and the validators that stand between a
// typo and an unmatchable profile.

import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/core/utils/validators.dart';
import 'package:lekkside_connect/features/applications/models/application.dart';
import 'package:lekkside_connect/features/matches/models/match_card.dart';
import 'package:lekkside_connect/features/passport/models/passport.dart';

void main() {
  group('Passport.gradeDisplay', () {
    Passport withGrade(double value, String scheme) => Passport(
          profileId: 'p1',
          gradeValue: value,
          gradeScheme: scheme,
        );

    test('renders each scheme in the student\'s own terms', () {
      expect(withGrade(78, 'percentage').gradeDisplay, '78%');
      expect(withGrade(3.4, 'gpa_4').gradeDisplay, '3.4 / 4.0');
      expect(withGrade(4.2, 'gpa_5').gradeDisplay, '4.2 / 5.0');
      expect(withGrade(34, 'ib').gradeDisplay, '34 / 45');
      expect(withGrade(5, 'a_level').gradeDisplay, '5 points');
    });

    test('maps WAEC numbers back to their letter grades', () {
      // Stored as 1-9 because that is what normalize_grade() expects, but a
      // student entered "C6" and should see "C6".
      expect(withGrade(1, 'waec').gradeDisplay, 'A1');
      expect(withGrade(6, 'waec').gradeDisplay, 'C6');
      expect(withGrade(9, 'waec').gradeDisplay, 'F9');
    });

    test('spells out UK classifications', () {
      expect(withGrade(1, 'uk_class').gradeDisplay, 'First class');
      expect(withGrade(2.1, 'uk_class').gradeDisplay, 'Upper second (2:1)');
      expect(withGrade(2.2, 'uk_class').gradeDisplay, 'Lower second (2:2)');
      expect(withGrade(3, 'uk_class').gradeDisplay, 'Third class');
    });

    test('says so when there is no grade', () {
      expect(const Passport(profileId: 'p1').gradeDisplay, 'Not added');
    });
  });

  group('Passport.budgetDisplay', () {
    test('formats a range and an open-ended maximum', () {
      expect(
        const Passport(
          profileId: 'p1',
          budgetMin: 5000,
          budgetMax: 30000,
          budgetCurrency: 'USD',
        ).budgetDisplay,
        'USD 5,000–30,000',
      );
      expect(
        const Passport(profileId: 'p1', budgetMax: 30000).budgetDisplay,
        'Up to USD 30,000',
      );
      expect(const Passport(profileId: 'p1').budgetDisplay, 'Not set');
    });
  });

  group('Passport.missingPieces', () {
    test('leads with the fields that gate matching', () {
      final missing = const Passport(profileId: 'p1').missingPieces;
      // Field, destination and level come first because without them there is
      // nothing for an institution to match against at all.
      expect(missing.first, 'Choose your field of study');
      expect(missing[1], 'Choose where you want to study');
      expect(missing[2], 'Choose your study level');
    });

    test('is empty once everything is filled in', () {
      final complete = Passport(
        profileId: 'p1',
        dateOfBirth: DateTime(2005, 3, 2),
        nationality: 'NG',
        currentCountry: 'NG',
        highestQualification: 'WASSCE',
        gradeValue: 78,
        gradeScheme: 'percentage',
        englishBand: 7,
        targetCountries: const ['CA'],
        targetLevels: const ['undergraduate'],
        targetFields: const ['computer-science'],
      );
      expect(complete.missingPieces, isEmpty);
    });
  });

  group('Passport.isMatchable', () {
    test('mirrors the database threshold', () {
      // min_completeness_to_match() is 50 in Postgres; below it, institutions
      // genuinely cannot see the student, so the UI must not claim otherwise.
      expect(const Passport(profileId: 'p1', completeness: 49).isMatchable,
          isFalse);
      expect(const Passport(profileId: 'p1', completeness: 50).isMatchable,
          isTrue);
    });
  });

  group('MatchCard', () {
    MatchCard card(int score, {List<MatchReason> reasons = const []}) =>
        MatchCard(
          programId: 'g1',
          score: score,
          reasons: reasons,
          computedAt: DateTime(2026, 1, 1),
        );

    test('bands the score into a label', () {
      expect(card(90).strengthLabel, 'Excellent match');
      expect(card(72).strengthLabel, 'Strong match');
      expect(card(58).strengthLabel, 'Good match');
      expect(card(42).strengthLabel, 'Possible match');
    });

    test('ranks reasons by weight, with the scholarship note last', () {
      final ranked = card(90, reasons: const [
        MatchReason(code: 'scholarship_available', weight: 0, detail: 'funds'),
        MatchReason(code: 'level_match', weight: 20, detail: 'level'),
        MatchReason(code: 'country_match', weight: 25, detail: 'country'),
      ]).rankedReasons;

      expect(ranked.map((r) => r.code).toList(), [
        'country_match',
        'level_match',
        // Weight 0 and not a scoring factor, so it reads as a note rather than
        // being buried among the reasons by weight.
        'scholarship_available',
      ]);
    });

    test('flags scholarships', () {
      expect(card(80).hasScholarship, isFalse);
      expect(
        card(80, reasons: const [
          MatchReason(code: 'scholarship_available', weight: 0, detail: 'f'),
        ]).hasScholarship,
        isTrue,
      );
    });
  });

  group('Application.availableActions', () {
    Application at(String stage) => Application(
          id: 'a1',
          profileId: 'p1',
          institutionId: 'i1',
          programId: 'g1',
          stage: stage,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('offers only what the database guard will actually allow', () {
      // guard_application_stage() is the authority; these lists exist so a
      // student is never shown a button that will be refused.
      expect(at('draft').availableActions, ['submitted']);
      expect(at('offer').availableActions, ['accepted', 'withdrawn']);
      expect(at('conditional_offer').availableActions,
          ['accepted', 'withdrawn']);
      expect(at('under_review').availableActions, ['withdrawn']);
    });

    test('offers nothing once the application is closed or settled', () {
      expect(at('rejected').availableActions, isEmpty);
      expect(at('withdrawn').availableActions, isEmpty);
      expect(at('enrolled').availableActions, isEmpty);
    });

    test('reports no progress for a closed application', () {
      // A rejection must not render as "nearly complete".
      expect(at('rejected').progress, 0);
      expect(at('withdrawn').progress, 0);
      expect(at('under_review').progress, greaterThan(0));
    });
  });

  group('AppValidators.validateGrade', () {
    test('accepts a value inside each scheme\'s range', () {
      expect(AppValidators.validateGrade('78', 'percentage'), isNull);
      expect(AppValidators.validateGrade('3.4', 'gpa_4'), isNull);
      expect(AppValidators.validateGrade('6', 'waec'), isNull);
      expect(AppValidators.validateGrade('2.1', 'uk_class'), isNull);
    });

    test('rejects values outside the scheme\'s range', () {
      expect(AppValidators.validateGrade('150', 'percentage'), isNotNull);
      expect(AppValidators.validateGrade('4.8', 'gpa_4'), isNotNull);
      expect(AppValidators.validateGrade('12', 'waec'), isNotNull);
    });

    test('rejects a WAEC grade that is not a whole number', () {
      // 6.5 is not a WAEC grade, and silently rounding it would misstate the
      // student's qualifications to every institution.
      expect(AppValidators.validateGrade('6.5', 'waec'), isNotNull);
    });

    test('rejects a UK classification that is not one of the four', () {
      expect(AppValidators.validateGrade('2.5', 'uk_class'), isNotNull);
    });

    test('insists on a scheme before a value can mean anything', () {
      expect(AppValidators.validateGrade('78', null), isNotNull);
    });
  });

  group('AppValidators.validateEnglishScore', () {
    test('accepts valid scores per test', () {
      expect(AppValidators.validateEnglishScore('6.5', 'ielts'), isNull);
      expect(AppValidators.validateEnglishScore('90', 'toefl'), isNull);
      expect(AppValidators.validateEnglishScore('120', 'duolingo'), isNull);
      expect(AppValidators.validateEnglishScore('62', 'pte'), isNull);
    });

    test('rejects a score on the wrong scale', () {
      // 90 is a fine TOEFL score and an impossible IELTS band.
      expect(AppValidators.validateEnglishScore('90', 'ielts'), isNotNull);
      expect(AppValidators.validateEnglishScore('200', 'toefl'), isNotNull);
    });

    test('rejects an IELTS band that is not a half step', () {
      expect(AppValidators.validateEnglishScore('6.3', 'ielts'), isNotNull);
    });

    test('skips validation when no test has been taken', () {
      expect(AppValidators.validateEnglishScore(null, 'none'), isNull);
    });
  });

  group('AppValidators.validatePassCode', () {
    test('accepts a well-formed code, with or without spacing', () {
      expect(AppValidators.validatePassCode('SQ53W4WS'), isNull);
      expect(AppValidators.validatePassCode('sq53 w4ws'), isNull);
    });

    test('rejects characters the generator never produces', () {
      // The alphabet excludes I, O, 0 and 1 so a misread code fails here
      // rather than silently resolving to another student's pass.
      expect(AppValidators.validatePassCode('SQ53W4W0'), isNotNull);
      expect(AppValidators.validatePassCode('IOIOIOIO'), isNotNull);
    });

    test('rejects the wrong length', () {
      expect(AppValidators.validatePassCode('SQ53W4W'), isNotNull);
    });
  });

  group('AppValidators.validateDateOfBirth', () {
    test('requires a plausible age for a prospective student', () {
      final now = DateTime.now();
      expect(
        AppValidators.validateDateOfBirth(DateTime(now.year - 20)),
        isNull,
      );
      expect(
        AppValidators.validateDateOfBirth(DateTime(now.year - 5)),
        isNotNull,
      );
      expect(AppValidators.validateDateOfBirth(null), isNotNull);
    });
  });

  group('AppValidators.validateEmail', () {
    test('accepts ordinary addresses, including long TLDs', () {
      expect(AppValidators.validateEmail('chidi@example.com'), isNull);
      // The previous pattern capped the TLD at four characters, which rejected
      // perfectly valid addresses.
      expect(AppValidators.validateEmail('a@university.education'), isNull);
      expect(AppValidators.validateEmail('admissions@univ.ac.uk'), isNull);
    });

    test('rejects obvious nonsense', () {
      expect(AppValidators.validateEmail('not-an-email'), isNotNull);
      expect(AppValidators.validateEmail('a@b'), isNotNull);
      expect(AppValidators.validateEmail(''), isNotNull);
    });
  });
}
