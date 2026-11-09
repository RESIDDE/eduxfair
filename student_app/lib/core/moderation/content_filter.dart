/// Catches objectionable text before it is posted.
///
/// App Review guideline 1.2 requires a UGC app to include "a method for
/// filtering objectionable material from being posted to the app". This is
/// that method, and it is the first of the four 1.2 obligations this app had
/// nothing for — reporting, blocking and contact details already existed.
///
/// What it is: a pattern filter over normalised text, in two tiers. What it
/// is not: a classifier. It will not catch everything, and it is not supposed
/// to be the only thing standing between a student and abuse — reports,
/// blocking and human review are the rest of it. Its job is to stop the
/// obvious cases at the moment of posting, where the cost of being wrong is
/// one retyped sentence.
///
/// Normalisation is most of the work. A list of plain words is defeated by
/// anyone who types `f u c k` or `sh1t`, so the text is folded first: case,
/// accents, leetspeak digits, repeated letters and the separators people put
/// between letters to get past exactly this kind of filter.
library;

enum FilterVerdict {
  /// Nothing matched.
  clean,

  /// Refuse the post outright. Reserved for the categories where there is no
  /// legitimate reading and no appeal worth having.
  block,

  /// Let it through, but flag it for review. Slurs and abuse sit here because
  /// context decides: a student quoting the abuse they received is not the
  /// same as a student sending it.
  review,
}

class FilterResult {
  final FilterVerdict verdict;

  /// Shown to the person posting. Null when [verdict] is clean.
  final String? message;

  /// Why it matched, for the moderation record rather than the author.
  final String? category;

  const FilterResult(this.verdict, {this.message, this.category});

  static const clean = FilterResult(FilterVerdict.clean);

  bool get isBlocked => verdict == FilterVerdict.block;
  bool get needsReview => verdict == FilterVerdict.review;
}

class ContentFilter {
  ContentFilter._();

  /// Categories with no legitimate reading in a feed about university
  /// admissions. Matching any of these refuses the post.
  ///
  /// Deliberately narrow. Everything arguable belongs in [_review], because a
  /// filter that blocks too much teaches people to work around it, and the
  /// ones who learn to work around it are the ones you least want to.
  static final _blocked = <String, List<RegExp>>{
    'child_safety': [
      // Sexual interest in minors, including the acronyms used to evade a
      // plain-word list.
      RegExp(r'\b(child|kid|minor|underage|preteen|teen)\s?(porn|nude|nudes|sex|xxx)\b'),
      RegExp(r'\bcp\s?(trade|swap|link|links)\b'),
      RegExp(r'\b(loli|shota)\b'),
    ],
    'threat': [
      RegExp(r'\bi\s?(will|am going to|gonna)\s?(kill|murder|stab|shoot)\s?(you|u|him|her|them)\b'),
      RegExp(r'\b(kill|hang|shoot)\s?your\s?self\b'),
      RegExp(r'\bkys\b'),
    ],
    'sexual_solicitation': [
      RegExp(r'\b(send|post|share)\s?(me\s?)?(your\s?)?(nudes?|naked\s?(pic|pics|photo|photos))\b'),
    ],
  };

  /// Held for review rather than refused.
  static final _review = <String, List<RegExp>>{
    'slur': [
      RegExp(r'\bn[i1]gg(a|er|ers|as)\b'),
      RegExp(r'\bf[a@]gg?(ot|ots|s)?\b'),
      RegExp(r'\b(retard|retarded|tranny|chink|spic|kike|wetback|coon)\b'),
    ],
    'harassment': [
      RegExp(r'\byou\s?(are|r)\s?(a\s?)?(worthless|pathetic|disgusting)\b'),
      RegExp(r'\b(go\s?)?die\s?in\s?a\s?(fire|hole|ditch)\b'),
    ],
    // The scam patterns that do the most damage in this particular app: a
    // student who believes a guaranteed visa can lose a year and a fee.
    // Note the `ioo`: these patterns run *after* normalisation, where
    // leetspeak has already turned `100%` into `ioo%`. A pattern written in
    // plain text against folded input silently never fires, which is the kind
    // of bug a filter can carry for years without anyone noticing.
    'admissions_fraud': [
      RegExp(r'\b(guaranteed|guarantee|sure)\s?(visa|admission|admissions|scholarship)\b'),
      RegExp(r'\b(ioo|100)\s?%\s?(visa|admission|admissions|scholarship)\b'),
      RegExp(r'\bvisa\s?(guarantee|guaranteed)\b'),
      RegExp(r'\b(pay|send)\s?(me|us)\s?\d+.{0,12}\b(admission|visa|scholarship|slot)\b'),
    ],
  };

  /// Folds the text so the patterns above see through obfuscation.
  ///
  /// Order matters: separators come out before leetspeak, or `n-1-g` would
  /// become `n-i-g` and still carry its hyphens into the word-boundary match.
  static String normalise(String input) {
    var text = input.toLowerCase();

    // Accents and lookalikes, reduced to their base letters.
    const folds = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'å': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n', 'ß': 'ss',
    };
    folds.forEach((from, to) => text = text.replaceAll(from, to));

    // Separators inserted between the letters of a single word: `f.u.c.k`,
    // `f u c k`, `f-u-c-k`.
    //
    // Both sides are zero-width assertions, which is the whole trick. An
    // earlier version consumed the letters either side, so in `f.u.c.k` the
    // match `f.u` moved the scan past `u` and the separator before `c` was
    // never looked at — it came out `fu.ck`. Matching only the separator lets
    // every one of them go in a single pass.
    //
    // The assertions also keep it off ordinary prose: `\b` before a letter
    // only holds when that letter starts a word, so the `o. H` in
    // "Hello there. How" is left alone.
    text = text.replaceAll(
      RegExp(r'(?<=\b[a-z0-9])[\s._\-*]+(?=[a-z0-9]\b)'),
      '',
    );

    // Leetspeak.
    const leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '\$': 's', '@': 'a'};
    leet.forEach((from, to) => text = text.replaceAll(from, to));

    // Stretched letters: `niiiiice`, `fuuuuck`. Three or more becomes one,
    // which leaves real doubles (`school`, `pass`) alone.
    text = text.replaceAllMapped(RegExp(r'(.)\1{2,}'), (m) => m[1]!);

    // Collapse whitespace so \b behaves predictably.
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Checks a post, comment, message or bio.
  static FilterResult check(String input) {
    if (input.trim().isEmpty) return FilterResult.clean;
    final text = normalise(input);

    for (final entry in _blocked.entries) {
      for (final pattern in entry.value) {
        if (pattern.hasMatch(text)) {
          return FilterResult(
            FilterVerdict.block,
            category: entry.key,
            message: _refusal(entry.key),
          );
        }
      }
    }

    for (final entry in _review.entries) {
      for (final pattern in entry.value) {
        if (pattern.hasMatch(text)) {
          return FilterResult(
            FilterVerdict.review,
            category: entry.key,
            message: _warning(entry.key),
          );
        }
      }
    }

    return FilterResult.clean;
  }

  /// Says which rule was broken without repeating the words back.
  static String _refusal(String category) => switch (category) {
        'child_safety' =>
          'This cannot be posted. Content that sexualises a minor is reported '
              'to the authorities, not just removed.',
        'threat' =>
          'This reads as a threat of violence, which is not allowed here. If '
              'you or someone else is in danger, contact your local '
              'emergency services.',
        'sexual_solicitation' =>
          'Asking anyone for sexual images is not allowed here, and this is a '
              'service used by people under 18.',
        _ => 'This breaks the Community Guidelines and cannot be posted.',
      };

  static String _warning(String category) => switch (category) {
        'slur' =>
          'This looks like it contains a slur. Posting it may get your '
              'account restricted — have another look before you send it.',
        'harassment' =>
          'This reads as abuse directed at a person. Have another look before '
              'you send it.',
        'admissions_fraud' =>
          'Guaranteeing a visa, an admission or a scholarship is not allowed '
              'here — students make expensive decisions on these claims.',
        _ => 'This may break the Community Guidelines.',
      };
}
