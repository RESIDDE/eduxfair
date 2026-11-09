/// A policy document, shipped in the app.
///
/// These live in the binary rather than behind a URL on purpose. App Review
/// guideline 2.1 rejects builds with non-functional URLs, and 5.1.1(i)
/// requires the privacy policy to be reachable "within the app in an easily
/// accessible manner" — a `launchUrl` to a marketing site satisfies neither if
/// the site is down, moved, or blocked on the reviewer's network.
class LegalDocument {
  final String title;

  /// Shown under the title — what this document is for, in one line.
  final String summary;

  /// The date the text last changed. Shown to the reader, because a policy
  /// without one cannot be reasoned about.
  final String lastUpdated;

  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.summary,
    required this.lastUpdated,
    required this.sections,
  });
}

class LegalSection {
  final String heading;

  /// Paragraphs. Rendered with spacing between them.
  final List<String> body;

  /// Bullet points shown after [body].
  final List<String> bullets;

  const LegalSection({
    required this.heading,
    this.body = const [],
    this.bullets = const [],
  });
}
