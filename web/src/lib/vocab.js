// Display labels for the Postgres enums.
//
// Mirrors student_app/lib/core/constants/app_constants.dart. The one that must
// NOT be hardcoded is field of study: it is a foreign key to
// `fields_of_study`, and matching compares a student's targets against it, so
// the pickers load that table instead (see useFieldsOfStudy).

export const STUDY_LEVELS = {
  foundation: 'Foundation',
  diploma: 'Diploma',
  undergraduate: 'Undergraduate',
  postgraduate: 'Postgraduate (Masters)',
  phd: 'PhD / Doctorate',
};

export const GRADING_SCHEMES = {
  waec: 'WAEC / NECO (A1–F9)',
  percentage: 'Percentage (0–100)',
  gpa_4: 'GPA (out of 4.0)',
  gpa_5: 'GPA (out of 5.0)',
  uk_class: 'UK classification',
  ib: 'IB diploma (out of 45)',
  a_level: 'A-Level points',
};

export const DOCUMENT_KINDS = {
  transcript: 'Academic transcript',
  certificate: 'Certificate / diploma',
  passport_id: 'Passport or national ID',
  english_test: 'English test result',
  cv: 'CV / résumé',
  recommendation: 'Recommendation letter',
  statement: 'Personal statement',
  financial: 'Proof of funds',
};

/** In pipeline order — the kanban columns are built from this. */
export const APPLICATION_STAGES = {
  draft: 'Draft',
  submitted: 'Submitted',
  under_review: 'Under review',
  documents_requested: 'Documents requested',
  conditional_offer: 'Conditional offer',
  offer: 'Offer',
  accepted: 'Offer accepted',
  deposit_paid: 'Deposit paid',
  visa: 'Visa stage',
  enrolled: 'Enrolled',
  rejected: 'Not successful',
  withdrawn: 'Withdrawn',
};

/**
 * The stages institution staff may set.
 *
 * `guard_application_stage()` in the database is the authority — notably
 * 'accepted' is the student's decision alone, and the trigger refuses it from
 * an institution. This list only decides which columns accept a drop.
 */
export const INSTITUTION_SETTABLE_STAGES = [
  'under_review',
  'documents_requested',
  'conditional_offer',
  'offer',
  'rejected',
  'deposit_paid',
  'visa',
  'enrolled',
];

/** Columns for the pipeline board, left to right. */
export const PIPELINE_COLUMNS = [
  'submitted',
  'under_review',
  'documents_requested',
  'conditional_offer',
  'offer',
  'accepted',
  'enrolled',
];

export const APPOINTMENT_STATUSES = {
  requested: 'Requested',
  confirmed: 'Confirmed',
  declined: 'Declined',
  rescheduled: 'Rescheduled',
  completed: 'Completed',
  no_show: 'No show',
  cancelled: 'Cancelled',
};

export const VERIFICATION_SUBJECTS = {
  institution: 'Institution',
  passport: 'Student passport',
  document: 'Document',
  educator: 'Educator',
};

export const INSTITUTION_TIERS = {
  basic: 'Basic',
  professional: 'Professional',
  enterprise: 'Enterprise',
};

export const COUNTRIES = {
  CA: 'Canada',
  GB: 'United Kingdom',
  US: 'United States',
  AU: 'Australia',
  DE: 'Germany',
  IE: 'Ireland',
  FR: 'France',
  NL: 'Netherlands',
  AE: 'United Arab Emirates',
  ZA: 'South Africa',
  MY: 'Malaysia',
  CY: 'Cyprus',
  NG: 'Nigeria',
  GH: 'Ghana',
  KE: 'Kenya',
  CM: 'Cameroon',
  UG: 'Uganda',
  TZ: 'Tanzania',
  ZW: 'Zimbabwe',
  RW: 'Rwanda',
  SN: 'Senegal',
  CI: "Côte d'Ivoire",
  ET: 'Ethiopia',
};

export const countryName = (code) => COUNTRIES[code] ?? code ?? '—';

/**
 * What each verification badge actually attests to.
 *
 * Kept next to the vocabulary because the wording is the product: overstating
 * it is the easiest way for the platform to mislead a student.
 */
export const VERIFICATION_MEANING = {
  institution:
    'Someone controlling an email address on the institution’s own domain ' +
    'confirmed this listing. Not a claim about accreditation or programme quality.',
  passport:
    'A reviewer checked the uploaded documents against the qualifications the ' +
    'student entered. Not a claim about the documents’ issuer.',
  document: 'A reviewer has seen this document and matched it to the student’s claims.',
  educator: 'This person’s affiliation with the institution has been confirmed.',
};
