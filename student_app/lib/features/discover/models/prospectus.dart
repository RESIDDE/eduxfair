import '../../../core/constants/app_constants.dart';
import 'institution.dart';
import 'program.dart';
import '../../../core/utils/formatters.dart';

/// The whole institution page, as `institution_prospectus()` returns it.
///
/// One call rather than seven: a student opening this on a Lagos mobile
/// connection should not wait on seven sequential round trips, and the entry
/// requirements have to be narrowed to their own country server-side, which
/// PostgREST cannot express as an embed.
class Prospectus {
  final Institution institution;
  final InstitutionProfile profile;
  final List<MediaItem> media;
  final List<Intake> intakes;
  final List<Scholarship> scholarships;
  final List<Contact> contacts;
  final List<Faq> faqs;
  final List<EntryRequirement> requirements;
  final List<Program> programs;

  /// The country the server resolved requirements against — the student's own,
  /// taken from their passport unless one was passed explicitly.
  final String? resolvedForCountry;

  const Prospectus({
    required this.institution,
    required this.profile,
    this.media = const [],
    this.intakes = const [],
    this.scholarships = const [],
    this.contacts = const [],
    this.faqs = const [],
    this.requirements = const [],
    this.programs = const [],
    this.resolvedForCountry,
  });

  List<MediaItem> get photos =>
      media.where((m) => m.kind == 'photo').toList();
  List<MediaItem> get brochures =>
      media.where((m) => m.kind == 'brochure').toList();

  /// The requirement that applies to this student, if the institution has
  /// published one. The server orders country-specific rules ahead of the
  /// general fallback, so the first is the most specific.
  EntryRequirement? get requirementForMe =>
      requirements.isEmpty ? null : requirements.first;

  /// Intakes still open, soonest first.
  List<Intake> get openIntakes {
    final now = DateTime.now();
    final open = intakes
        .where((i) => i.applicationsClose == null || i.applicationsClose!.isAfter(now))
        .toList()
      ..sort((a, b) => (a.termStarts ?? DateTime(2100))
          .compareTo(b.termStarts ?? DateTime(2100)));
    return open;
  }

  factory Prospectus.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) make) =>
        (json[key] as List? ?? const [])
            .map((e) => make((e as Map).cast<String, dynamic>()))
            .toList();

    return Prospectus(
      institution: Institution.fromMap(
        (json['institution'] as Map).cast<String, dynamic>()),
      profile: InstitutionProfile.fromMap(
        (json['profile'] as Map?)?.cast<String, dynamic>() ?? const {}),
      media: list('media', MediaItem.fromMap),
      intakes: list('intakes', Intake.fromMap),
      scholarships: list('scholarships', Scholarship.fromMap),
      contacts: list('contacts', Contact.fromMap),
      faqs: list('faqs', Faq.fromMap),
      requirements: list('requirements', EntryRequirement.fromMap),
      programs: list('programs', Program.fromMap),
      resolvedForCountry: json['resolved_for_country'] as String?,
    );
  }
}

class InstitutionProfile {
  final String? tagline;
  final String? about;
  final String? campusLife;
  final String? accommodation;
  final int? foundedYear;
  final int? studentCount;
  final int? internationalStudentCount;
  final double? costOfLivingMin;
  final double? costOfLivingMax;
  final String costCurrency;
  final double? applicationFee;
  final double? deposit;
  final String feeCurrency;
  final List<String> accreditation;
  final List<Ranking> rankings;
  final Map<String, String> socials;
  final List<ApplicationStep> applicationSteps;
  final int completeness;

  const InstitutionProfile({
    this.tagline,
    this.about,
    this.campusLife,
    this.accommodation,
    this.foundedYear,
    this.studentCount,
    this.internationalStudentCount,
    this.costOfLivingMin,
    this.costOfLivingMax,
    this.costCurrency = 'USD',
    this.applicationFee,
    this.deposit,
    this.feeCurrency = 'USD',
    this.accreditation = const [],
    this.rankings = const [],
    this.socials = const {},
    this.applicationSteps = const [],
    this.completeness = 0,
  });

  String? get costOfLivingDisplay {
    if (costOfLivingMax == null) return null;
    final max = formatThousands(costOfLivingMax!.round());
    if (costOfLivingMin == null) return 'Up to $costCurrency $max / year';
    return '$costCurrency ${formatThousands(costOfLivingMin!.round())}–$max / year';
  }


  factory InstitutionProfile.fromMap(Map<String, dynamic> map) =>
      InstitutionProfile(
        tagline: map['tagline'] as String?,
        about: map['about'] as String?,
        campusLife: map['campus_life'] as String?,
        accommodation: map['accommodation'] as String?,
        foundedYear: (map['founded_year'] as num?)?.toInt(),
        studentCount: (map['student_count'] as num?)?.toInt(),
        internationalStudentCount:
            (map['international_student_count'] as num?)?.toInt(),
        costOfLivingMin: (map['cost_of_living_min'] as num?)?.toDouble(),
        costOfLivingMax: (map['cost_of_living_max'] as num?)?.toDouble(),
        costCurrency: map['cost_currency'] as String? ?? 'USD',
        applicationFee: (map['application_fee'] as num?)?.toDouble(),
        deposit: (map['deposit'] as num?)?.toDouble(),
        feeCurrency: map['fee_currency'] as String? ?? 'USD',
        accreditation: (map['accreditation'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        rankings: (map['rankings'] as List? ?? const [])
            .map((e) => Ranking.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
        socials: (map['socials'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        applicationSteps: (map['application_steps'] as List? ?? const [])
            .map((e) =>
                ApplicationStep.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
        completeness: (map['completeness'] as num?)?.toInt() ?? 0,
      );
}

class Ranking {
  final String body;
  final int? rank;
  final int? year;

  const Ranking({required this.body, this.rank, this.year});

  String get display => rank == null
      ? body
      : '#$rank $body${year == null ? '' : ' · $year'}';

  factory Ranking.fromMap(Map<String, dynamic> map) => Ranking(
        body: map['body'] as String? ?? '',
        rank: (map['rank'] as num?)?.toInt(),
        year: (map['year'] as num?)?.toInt(),
      );
}

class ApplicationStep {
  final String title;
  final String? detail;

  const ApplicationStep({required this.title, this.detail});

  factory ApplicationStep.fromMap(Map<String, dynamic> map) => ApplicationStep(
        title: map['title'] as String? ?? '',
        detail: map['detail'] as String?,
      );
}

class MediaItem {
  final String id;
  final String kind;
  final String? storagePath;
  final String? externalUrl;
  final String? caption;

  const MediaItem({
    required this.id,
    required this.kind,
    this.storagePath,
    this.externalUrl,
    this.caption,
  });

  factory MediaItem.fromMap(Map<String, dynamic> map) => MediaItem(
        id: map['id'] as String,
        kind: map['kind'] as String? ?? 'photo',
        storagePath: map['storage_path'] as String?,
        externalUrl: map['external_url'] as String?,
        caption: map['caption'] as String?,
      );
}

class Intake {
  final String id;
  final String label;
  final DateTime? applicationsOpen;
  final DateTime? applicationsClose;
  final DateTime? termStarts;

  const Intake({
    required this.id,
    required this.label,
    this.applicationsOpen,
    this.applicationsClose,
    this.termStarts,
  });

  /// Days until applications close. Negative once it has passed.
  int? get daysToClose =>
      applicationsClose?.difference(DateTime.now()).inDays;

  bool get isClosingSoon {
    final days = daysToClose;
    return days != null && days >= 0 && days <= 30;
  }

  static DateTime? _date(dynamic v) {
    final raw = v?.toString();
    return raw == null ? null : DateTime.parse(raw);
  }

  factory Intake.fromMap(Map<String, dynamic> map) => Intake(
        id: map['id'] as String,
        label: map['label'] as String,
        applicationsOpen: _date(map['applications_open']),
        applicationsClose: _date(map['applications_close']),
        termStarts: _date(map['term_starts']),
      );
}

class Scholarship {
  final String id;
  final String name;
  final double? amount;
  final String currency;
  final String? coverage;
  final String? criteria;
  final DateTime? deadline;
  final String? url;

  const Scholarship({
    required this.id,
    required this.name,
    this.amount,
    this.currency = 'USD',
    this.coverage,
    this.criteria,
    this.deadline,
    this.url,
  });

  String get valueDisplay {
    if (coverage != null && coverage!.isNotEmpty) return coverage!;
    if (amount != null) {
      return '$currency ${formatThousands(amount!.round())}';
    }
    return 'Varies';
  }

  factory Scholarship.fromMap(Map<String, dynamic> map) => Scholarship(
        id: map['id'] as String,
        name: map['name'] as String,
        amount: (map['amount'] as num?)?.toDouble(),
        currency: map['currency'] as String? ?? 'USD',
        coverage: map['coverage'] as String?,
        criteria: map['criteria'] as String?,
        deadline: Intake._date(map['deadline']),
        url: map['url'] as String?,
      );
}

class Contact {
  final String id;
  final String role;
  final String? name;
  final String? email;
  final String? phone;

  const Contact({
    required this.id,
    required this.role,
    this.name,
    this.email,
    this.phone,
  });

  factory Contact.fromMap(Map<String, dynamic> map) => Contact(
        id: map['id'] as String,
        role: map['role'] as String,
        name: map['name'] as String?,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
      );
}

class Faq {
  final String id;
  final String question;
  final String answer;

  const Faq({required this.id, required this.question, required this.answer});

  factory Faq.fromMap(Map<String, dynamic> map) => Faq(
        id: map['id'] as String,
        question: map['question'] as String,
        answer: map['answer'] as String,
      );
}

/// What this student needs, from their own country.
class EntryRequirement {
  final String id;
  final String? fromCountry;
  final String? level;
  final String? qualification;
  final double? minGradeValue;
  final String? minGradeScheme;
  final double? minEnglishBand;
  final List<String> additional;
  final String? note;

  const EntryRequirement({
    required this.id,
    this.fromCountry,
    this.level,
    this.qualification,
    this.minGradeValue,
    this.minGradeScheme,
    this.minEnglishBand,
    this.additional = const [],
    this.note,
  });

  /// True when this rule was written for the student's own country rather than
  /// being the general fallback — worth saying so on screen.
  bool get isCountrySpecific => fromCountry != null;

  String get levelLabel =>
      level == null ? 'Any level' : AppConstants.studyLevels[level] ?? level!;

  String get englishDisplay => minEnglishBand == null
      ? 'Not published'
      : 'IELTS ${minEnglishBand!.toStringAsFixed(1)} or equivalent';

  factory EntryRequirement.fromMap(Map<String, dynamic> map) => EntryRequirement(
        id: map['id'] as String,
        fromCountry: map['from_country'] as String?,
        level: map['level'] as String?,
        qualification: map['qualification'] as String?,
        minGradeValue: (map['min_grade_value'] as num?)?.toDouble(),
        minGradeScheme: map['min_grade_scheme'] as String?,
        minEnglishBand: (map['min_english_band'] as num?)?.toDouble(),
        additional: (map['additional'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        note: map['note'] as String?,
      );
}
