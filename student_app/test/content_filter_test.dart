// The post-time filter required by App Review guideline 1.2.
//
// Two failure modes matter and they pull against each other: letting the
// obvious cases through, and blocking ordinary sentences. The false-positive
// group is the longer one on purpose — a filter that blocks real posts about
// university admissions is worse than useless here, because it teaches people
// to route around it.

import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/core/moderation/content_filter.dart';

void main() {
  group('leaves ordinary posts alone', () {
    const fine = [
      'Global Futures Scholarship closes in 14 days. Full tuition, ten awards.',
      'Does anyone know the IELTS requirement for Maplecrest?',
      'I passed! Offer letter came through this morning 🎉',
      'The visa appointment queue in Lagos is about three weeks right now.',
      'My classmate said the accommodation deposit is refundable — is that right?',
      'Assess my chances: 3.6 GPA, IELTS 7.5, applying to Canada.',
      'Good luck everyone writing WAEC this week.',
      // Doubled letters that the stretch-collapsing must not mangle.
      'School fees, pass marks, committee meeting, accommodation address.',
      // "kid" and "teen" in innocent contexts — the child-safety patterns
      // require a sexual term alongside them.
      'I teach a kids coding club at the weekend.',
      'Teen applicants need a guardian signature on the form.',
    ];
    for (final text in fine) {
      test('"${text.substring(0, text.length.clamp(0, 44))}…"', () {
        expect(ContentFilter.check(text).verdict, FilterVerdict.clean);
      });
    }
  });

  group('refuses what has no legitimate reading', () {
    test('sexualising a minor', () {
      expect(ContentFilter.check('selling child porn here').verdict,
          FilterVerdict.block);
      expect(ContentFilter.check('underage nudes dm me').verdict,
          FilterVerdict.block);
    });

    test('a threat of violence', () {
      expect(ContentFilter.check('i will kill you').verdict,
          FilterVerdict.block);
      expect(ContentFilter.check('kys').verdict, FilterVerdict.block);
    });

    test('asking for sexual images', () {
      expect(ContentFilter.check('send me your nudes').verdict,
          FilterVerdict.block);
    });

    test('the reason names a category, and never repeats the words back', () {
      final result = ContentFilter.check('i will kill you');
      expect(result.category, 'threat');
      expect(result.message, isNotNull);
      expect(result.message, isNot(contains('kill')));
    });
  });

  group('holds the arguable cases for review rather than refusing them', () {
    test('a slur', () {
      expect(ContentFilter.check('you absolute retard').verdict,
          FilterVerdict.review);
    });

    test('admissions fraud, which is the scam this app actually attracts', () {
      expect(ContentFilter.check('guaranteed visa for 500k').verdict,
          FilterVerdict.review);
      expect(ContentFilter.check('100% admission, pay me today').verdict,
          FilterVerdict.review);
    });

    test('review is not refusal — the post is still allowed to go', () {
      final result = ContentFilter.check('guaranteed scholarship');
      expect(result.isBlocked, isFalse);
      expect(result.needsReview, isTrue);
    });
  });

  group('sees through the obfuscation a plain word list misses', () {
    test('spaced out', () {
      expect(ContentFilter.check('k y s').verdict, FilterVerdict.block);
    });

    test('punctuation between letters', () {
      expect(ContentFilter.check('k.y.s').verdict, FilterVerdict.block);
      expect(ContentFilter.check('k-y-s').verdict, FilterVerdict.block);
    });

    test('leetspeak', () {
      expect(ContentFilter.check('n1gger').verdict, FilterVerdict.review);
    });

    test('stretched letters', () {
      expect(ContentFilter.check('kyyyys').verdict, FilterVerdict.block);
    });

    test('mixed case and accents', () {
      expect(ContentFilter.check('I WILL KÍLL YOU').verdict,
          FilterVerdict.block);
    });
  });

  group('normalisation', () {
    test('folds separators only between single letters', () {
      expect(ContentFilter.normalise('f.u.c.k'), 'fuck');
      // Real sentences keep their shape.
      expect(ContentFilter.normalise('Hello there. How are you?'),
          'hello there. how are you?');
    });

    test('collapses stretched letters but keeps genuine doubles', () {
      expect(ContentFilter.normalise('sooooo'), 'so');
      expect(ContentFilter.normalise('school'), 'school');
      expect(ContentFilter.normalise('pass'), 'pass');
    });

    test('empty input is clean, not an error', () {
      expect(ContentFilter.check('').verdict, FilterVerdict.clean);
      expect(ContentFilter.check('   ').verdict, FilterVerdict.clean);
    });
  });
}
