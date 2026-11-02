-- Lekkside Connect — reference vocabulary.
--
-- This is a migration rather than seed data because matching depends on both
-- sides using the same subject slugs. If a program says 'computer-science' and
-- a student says 'comp-sci', the match silently never happens — so the
-- vocabulary ships with the schema and the UI must select from it.

insert into fields_of_study (slug, label, sort_order) values
  ('computer-science',        'Computer Science & IT',             10),
  ('engineering',             'Engineering',                       20),
  ('business',                'Business & Management',             30),
  ('accounting-finance',      'Accounting & Finance',              40),
  ('health-sciences',         'Health Sciences',                   50),
  ('nursing',                 'Nursing & Midwifery',               60),
  ('medicine',                'Medicine & Surgery',                70),
  ('pharmacy',                'Pharmacy',                          80),
  ('law',                     'Law',                               90),
  ('education',               'Education & Teaching',             100),
  ('social-sciences',         'Social Sciences',                  110),
  ('economics',               'Economics',                        120),
  ('agriculture',             'Agriculture & Food Science',       130),
  ('architecture',            'Architecture & Built Environment', 140),
  ('arts-humanities',         'Arts & Humanities',                150),
  ('media-communication',     'Media & Communication',            160),
  ('hospitality-tourism',     'Hospitality & Tourism',            170),
  ('natural-sciences',        'Natural Sciences',                 180),
  ('mathematics-statistics',  'Mathematics & Statistics',         190),
  ('psychology',              'Psychology',                       200),
  ('public-health',           'Public Health',                    210),
  ('data-science',            'Data Science & Analytics',         220),
  ('cybersecurity',           'Cybersecurity',                    230),
  ('aviation',                'Aviation & Aeronautics',           240),
  ('environmental-science',   'Environmental Science',            250)
on conflict (slug) do update set label = excluded.label,
                                 sort_order = excluded.sort_order;
