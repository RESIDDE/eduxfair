/// An entry from `public.fields_of_study`.
///
/// This is a controlled vocabulary, not free text, and that matters: matching
/// compares a student's `target_fields` against `programs.field_of_study`, so a
/// typed-in subject would make the student silently unmatchable. Always load
/// these and let the student pick.
class FieldOfStudy {
  final String slug;
  final String label;
  final int sortOrder;

  const FieldOfStudy({
    required this.slug,
    required this.label,
    this.sortOrder = 100,
  });

  factory FieldOfStudy.fromMap(Map<String, dynamic> map) => FieldOfStudy(
        slug: map['slug'] as String,
        label: map['label'] as String,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 100,
      );
}
