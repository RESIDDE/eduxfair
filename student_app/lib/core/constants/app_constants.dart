import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide constants: route names, environment config and the handful of
/// domain vocabularies the UI has to agree with the database on.
class AppConstants {
  AppConstants._();

  // ── App info ──────────────────────────────────────────────────────────────
  static const String appName = 'Eduxfair';
  static const String appTagline = 'One passport. Every education fair.';
  static const String appVersion = '1.0.0';
  static const String appLogoPath = 'assets/images/logo.png';

  static const String supportEmail = 'support@educationfair.com.ng';

  static const String termsUrl = 'https://educationfair.com.ng/terms';
  static const String privacyUrl = 'https://educationfair.com.ng/privacy';

  // ── Environment ───────────────────────────────────────────────────────────
  // Read from .env (bundled as an asset) so the same build can be pointed at a
  // staging project. The anon key is safe to ship: RLS is what protects data,
  // and it is the service-role key that must never appear in a client.
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ── Storage buckets ───────────────────────────────────────────────────────
  static const String bucketPassportDocs = 'passport-docs';
  static const String bucketAvatars = 'avatars';
  static const String bucketMessageAttachments = 'message-attachments';
  static const String bucketInstitutionLogos = 'institution-logos';
  static const String bucketInstitutionMedia = 'institution-media';
  static const String bucketPostMedia = 'post-media';

  // ── Email confirmation ────────────────────────────────────────────────────
  // Custom 6-digit OTP verification code dispatched via Resend and validated
  // against account_otps.
  static const int otpLength = 6;

  // ── Routes ────────────────────────────────────────────────────────────────
  static const String routeSplash = '/';
  static const String routeOnboarding = '/onboarding';
  static const String routeLogin = '/login';
  /// The fork: student or organisation. Sign-up starts here, not at a form.
  static const String routeSignup = '/signup';
  static const String routeRegister = '/register';
  static const String routeRegisterInstitution = '/register/institution';
  static const String routeOtp = '/otp';
  static const String routeForgotPassword = '/forgot-password';
  static const String routeWrongApp = '/wrong-app';

  // ── Organisation kinds ────────────────────────────────────────────────────
  // Mirrors the `institution_kind` enum. The kind decides what a listing is
  // *for* — an embassy has visa routes and no programs — so it is asked at
  // signup rather than inferred later.
  static const Map<String, String> institutionKinds = {
    'university': 'University',
    'college': 'College or polytechnic',
    'embassy': 'Embassy or high commission',
    'agency': 'Education agency',
  };

  /// One line per kind, shown under the choice so the wrong one is not picked.
  static const Map<String, String> institutionKindBlurbs = {
    'university': 'Degree programs, scholarships and intakes.',
    'college': 'Diplomas, foundation and pathway programs.',
    'embassy': 'Visa guidance and requirements for your country.',
    'agency': 'Represent institutions and guide applicants.',
  };

  // ── Institution routes ────────────────────────────────────────────────────
  // Staff get their own shell in this same app, chosen by role in the router.
  // There is no separate console to send anyone to.
  static const String routeOrgSetup = '/org/setup';
  static const String routeOrgHome = '/org';
  static const String routeOrgProfile = '/org/page';
  static const String routeOrgPosts = '/org/posts';
  static const String routeOrgSpaces = '/org/spaces';
  static const String routeOrgMore = '/org/more';

  static const String routeOrgStudents = '/org/students';
  static const String routeOrgPipeline = '/org/pipeline';
  static const String routeOrgInbox = '/org/inbox';
  static const String routeOrgAppointments = '/org/appointments';
  static const String routeOrgPrograms = '/org/programs';
  static const String routeOrgFairs = '/org/fairs';
  static const String routeOrgTeam = '/org/team';
  static const String routeOrgFollowers = '/org/followers';
  static const String routeOrgSettings = '/org/settings';

  static const String routeHome = '/home';
  static const String routePassport = '/passport';
  static const String routeDiscover = '/discover';
  static const String routeMatches = '/matches';
  static const String routeMessages = '/messages';
  static const String routeProfile = '/profile';
  static const String routeStudentFollowers = '/followers';

  static const String routePassportEdit = '/passport/edit';
  static const String routeDocuments = '/passport/documents';
  static const String routeSharing = '/passport/sharing';
  static const String routeInstitution = '/institution';
  static const String routeProgram = '/program';
  static const String routeAppointments = '/appointments';
  static const String routeAppointmentRequest = '/appointments/request';
  static const String routeChat = '/messages/chat';
  static const String routeApplications = '/applications';
  static const String routeApplicationDetail = '/applications/detail';
  static const String routeFairPassport = '/fairs/passport';
  static const String routeFairReport = '/fairs/report';
  static const String routeNotifications = '/notifications';
  static const String routeSaved = '/saved';
  static const String routeFeed = '/feed';
  static const String routeSearch = '/search';
  static const String routeSpaces = '/spaces';
  static const String routeSpaceDetail = '/spaces/s';

  /// `/call/space/:id` and `/call/appointment/:id`. One route for both kinds,
  /// because one screen serves both.
  static const String routeCall = '/call';
  static const String routePost = '/post';
  static const String routeCompose = '/compose';
  static const String routeHandle = '/u';

  // ── Domain vocabularies ───────────────────────────────────────────────────
  // These mirror the Postgres enums. Matching compares target fields against
  // `programs.field_of_study`, which is a foreign key to `fields_of_study`, so
  // the picker MUST load that table rather than let anyone type a subject in —
  // a mismatched slug makes a student silently unmatchable.

  /// Mirrors the `space_kind` enum. The kind decides the label and the icon,
  /// which is why it is asked at scheduling time rather than guessed from the
  /// title.
  static const Map<String, String> spaceKinds = {
    'admissions_hour': 'Admissions hour',
    'scholarship_qa': 'Scholarship Q&A',
    'country_briefing': 'Country briefing',
    'open_day': 'Open day',
  };

  /// One line per kind, shown under the choice when scheduling one.
  static const Map<String, String> spaceKindBlurbs = {
    'admissions_hour': 'Open questions about applying.',
    'scholarship_qa': 'Funding, awards and who qualifies.',
    'country_briefing': 'Visas, costs and living there.',
    'open_day': 'A tour of the institution and its programs.',
  };

  /// Mirrors the `study_level` enum.
  static const Map<String, String> studyLevels = {
    'foundation': 'Foundation',
    'diploma': 'Diploma',
    'undergraduate': 'Undergraduate',
    'postgraduate': 'Postgraduate (Masters)',
    'phd': 'PhD / Doctorate',
  };

  /// Mirrors the `grading_scheme` enum, with the hint text each one needs.
  static const Map<String, String> gradingSchemes = {
    'waec': 'WAEC / NECO (A1–F9)',
    'percentage': 'Percentage (0–100)',
    'gpa_4': 'GPA (out of 4.0)',
    'gpa_5': 'GPA (out of 5.0)',
    'uk_class': 'UK classification',
    'ib': 'IB diploma (out of 45)',
    'a_level': 'A-Level points',
  };

  /// Mirrors the `english_test` enum.
  static const Map<String, String> englishTests = {
    'none': 'Not taken yet',
    'ielts': 'IELTS',
    'toefl': 'TOEFL iBT',
    'duolingo': 'Duolingo English Test',
    'pte': 'PTE Academic',
    'waec_english': 'WAEC English',
  };

  /// Mirrors the `document_kind` enum.
  static const Map<String, String> documentKinds = {
    'transcript': 'Academic transcript',
    'certificate': 'Certificate / diploma',
    'passport_id': 'Passport or national ID',
    'english_test': 'English test result',
    'cv': 'CV / résumé',
    'recommendation': 'Recommendation letter',
    'statement': 'Personal statement',
    'financial': 'Proof of funds',
  };

  /// Mirrors the `application_stage` enum, in pipeline order.
  static const Map<String, String> applicationStages = {
    'draft': 'Draft',
    'submitted': 'Submitted',
    'under_review': 'Under review',
    'documents_requested': 'Documents requested',
    'conditional_offer': 'Conditional offer',
    'offer': 'Offer',
    'accepted': 'Offer accepted',
    'deposit_paid': 'Deposit paid',
    'visa': 'Visa stage',
    'enrolled': 'Enrolled',
    'rejected': 'Not successful',
    'withdrawn': 'Withdrawn',
  };

  /// The stages a student may move an application to themselves. Enforced by
  /// `guard_application_stage()` in the database — this list only decides which
  /// buttons to render, and the server remains the authority.
  static const Set<String> studentSettableStages = {
    'draft', 'submitted', 'accepted', 'withdrawn',
  };

  /// Common intake labels. Free text in the schema, so these are suggestions.
  static const List<String> intakes = [
    'Fall 2026', 'Winter 2027', 'Spring 2027', 'Summer 2027',
    'January 2027', 'September 2026', 'September 2027',
  ];

  /// Countries students most often target, for the picker's top section.
  static const Map<String, String> popularDestinations = {
    'CA': 'Canada',
    'GB': 'United Kingdom',
    'US': 'United States',
    'AU': 'Australia',
    'DE': 'Germany',
    'IE': 'Ireland',
    'FR': 'France',
    'NL': 'Netherlands',
    'AE': 'United Arab Emirates',
    'ZA': 'South Africa',
    'MY': 'Malaysia',
    'CY': 'Cyprus',
  };

  /// Where students are applying from.
  static const Map<String, String> homeCountries = {
    'NG': 'Nigeria',
    'GH': 'Ghana',
    'KE': 'Kenya',
    'CM': 'Cameroon',
    'UG': 'Uganda',
    'TZ': 'Tanzania',
    'ZW': 'Zimbabwe',
    'ZA': 'South Africa',
    'RW': 'Rwanda',
    'SN': 'Senegal',
    'CI': "Côte d'Ivoire",
    'ET': 'Ethiopia',
  };

  /// A passport below this is not matched at all, mirroring
  /// `min_completeness_to_match()`. Shown as the target on the progress meter.
  static const int minCompletenessToMatch = 50;
}
