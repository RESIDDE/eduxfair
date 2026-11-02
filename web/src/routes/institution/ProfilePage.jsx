import { useState } from 'react';
import {
  BookOpen,
  CalendarRange,
  GraduationCap,
  Image as ImageIcon,
  Mail,
  MessageCircleQuestion,
  Plus,
  Save,
  Trash2,
  Wallet,
} from 'lucide-react';
import {
  Alert,
  Button,
  CardHeader,
  Dialog,
  Field,
  Input,
  Loading,
  Select,
  SurfaceCard,
  Textarea,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { COUNTRIES, GRADING_SCHEMES, STUDY_LEVELS } from '../../lib/vocab';

/**
 * The institution's public page, edited.
 *
 * Everything here is what a student is actually weighing up — cost of living,
 * whether their own qualifications clear the bar, when applications close,
 * whether there is funding. The old settings page covered name, country and a
 * paragraph, which answers none of it.
 *
 * `completeness` comes back from a database trigger rather than being computed
 * here, so the number the console nudges with is the same one that will gate
 * featured placement in discovery.
 */
export default function ProfilePage() {
  const { institutionId, institution } = useAuth();

  const { data: profile, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('institution_profiles')
        .select('*')
        .eq('institution_id', institutionId)
        .maybeSingle(),
    [institutionId],
  );

  if (loading) return <Loading label="Loading your page" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  return (
    <div className="flex flex-col gap-5 pb-4 max-w-[900px]">
      <CompletenessCard profile={profile} institution={institution} />
      <AboutSection profile={profile} institutionId={institutionId} onSaved={reload} />
      <CostSection profile={profile} institutionId={institutionId} onSaved={reload} />
      <CredibilitySection profile={profile} institutionId={institutionId} onSaved={reload} />

      <ListSection
        icon={ImageIcon}
        title="Gallery"
        subtitle="Photos of the campus, residences and students. The first becomes the header."
        table="institution_media"
        institutionId={institutionId}
        order="ord"
        columns={[
          { key: 'caption', label: 'Caption', render: (r) => r.caption ?? '—' },
          { key: 'kind', label: 'Kind', render: (r) => r.kind.replace('_', ' ') },
        ]}
        fields={[
          { key: 'kind', label: 'Kind', type: 'select',
            options: { photo: 'Photo', brochure: 'Brochure (PDF)', video_link: 'Video link' },
            default: 'photo' },
          { key: 'external_url', label: 'Video URL',
            hint: 'Only for a video link — YouTube or Vimeo.' },
          { key: 'caption', label: 'Caption' },
        ]}
        upload={{ bucket: 'institution-media', column: 'storage_path' }}
      />

      <ListSection
        icon={CalendarRange}
        title="Intakes"
        subtitle="When applications open and close, and when term starts."
        table="institution_intakes"
        institutionId={institutionId}
        columns={[
          { key: 'label', label: 'Intake' },
          { key: 'applications_close', label: 'Applications close' },
          { key: 'term_starts', label: 'Term starts' },
        ]}
        fields={[
          { key: 'label', label: 'Label', required: true, placeholder: 'Fall 2026' },
          { key: 'applications_open', label: 'Applications open', type: 'date' },
          { key: 'applications_close', label: 'Applications close', type: 'date' },
          { key: 'term_starts', label: 'Term starts', type: 'date' },
        ]}
      />

      <ListSection
        icon={GraduationCap}
        title="Entry requirements"
        subtitle="Set a general rule, then override it per country. Students see the one that applies to them."
        table="institution_entry_requirements"
        institutionId={institutionId}
        columns={[
          { key: 'from_country', label: 'From',
            render: (r) => (r.from_country ? COUNTRIES[r.from_country] ?? r.from_country : 'Anywhere') },
          { key: 'level', label: 'Level',
            render: (r) => (r.level ? STUDY_LEVELS[r.level] : 'Any level') },
          { key: 'qualification', label: 'Qualification' },
        ]}
        fields={[
          { key: 'from_country', label: 'Applies to students from', type: 'select',
            options: COUNTRIES, allowEmpty: 'Anywhere' },
          { key: 'level', label: 'Study level', type: 'select',
            options: STUDY_LEVELS, allowEmpty: 'Any level' },
          { key: 'qualification', label: 'Qualification',
            placeholder: 'WASSCE with five credits including English' },
          { key: 'min_grade_value', label: 'Minimum grade', type: 'number' },
          { key: 'min_grade_scheme', label: 'Grading scheme', type: 'select',
            options: GRADING_SCHEMES, allowEmpty: 'Not specified' },
          { key: 'min_english_band', label: 'English (IELTS or equivalent)',
            type: 'number', step: '0.5' },
          { key: 'note', label: 'Anything else', type: 'textarea' },
        ]}
      />

      <ListSection
        icon={Wallet}
        title="Scholarships"
        subtitle="Funding is often what decides whether a matched student can actually come."
        table="institution_scholarships"
        institutionId={institutionId}
        columns={[
          { key: 'name', label: 'Award' },
          { key: 'coverage', label: 'Covers' },
          { key: 'deadline', label: 'Deadline' },
        ]}
        fields={[
          { key: 'name', label: 'Name', required: true },
          { key: 'coverage', label: 'What it covers', placeholder: '50% of tuition' },
          { key: 'amount', label: 'Amount', type: 'number' },
          { key: 'criteria', label: 'Who qualifies', type: 'textarea' },
          { key: 'deadline', label: 'Deadline', type: 'date' },
          { key: 'url', label: 'Link' },
        ]}
      />

      <ListSection
        icon={Mail}
        title="Contacts"
        subtitle="Who a student should reach, and for what."
        table="institution_contacts"
        institutionId={institutionId}
        columns={[
          { key: 'role', label: 'Role' },
          { key: 'name', label: 'Name' },
          { key: 'email', label: 'Email' },
        ]}
        fields={[
          { key: 'role', label: 'Role', required: true,
            placeholder: 'International admissions' },
          { key: 'name', label: 'Name' },
          { key: 'email', label: 'Email', type: 'email' },
          { key: 'phone', label: 'Phone' },
        ]}
      />

      <ListSection
        icon={MessageCircleQuestion}
        title="Questions students ask"
        subtitle="Answer the common ones once instead of in every message."
        table="institution_faqs"
        institutionId={institutionId}
        columns={[{ key: 'question', label: 'Question' }]}
        fields={[
          { key: 'question', label: 'Question', required: true },
          { key: 'answer', label: 'Answer', type: 'textarea', required: true },
        ]}
      />
    </div>
  );
}

// ── Completeness ────────────────────────────────────────────────────────────

function CompletenessCard({ profile, institution }) {
  const value = profile?.completeness ?? 0;
  const tone = value >= 70 ? 'text-success' : value >= 40 ? 'text-warning' : 'text-error';

  return (
    <SurfaceCard className="p-6">
      <div className="flex items-start gap-5 flex-wrap">
        <div className="size-12 rounded-tile bg-accent/12 grid place-items-center shrink-0">
          <BookOpen size={22} className="text-accent" strokeWidth={2.1} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-3">
            <h2 className="font-bold text-[16px]">{institution?.name}</h2>
            <span className={`text-[22px] font-extrabold tabular-nums ${tone}`}>
              {value}%
            </span>
          </div>
          <p className="mt-1.5 text-[13px] text-muted leading-relaxed max-w-prose">
            {value >= 70
              ? 'Your page answers what students actually ask. Keep intakes and '
                + 'deadlines current and it stays useful.'
              : 'Students compare institutions on cost, entry requirements and '
                + 'deadlines. Pages that answer those get opened; pages that do '
                + 'not get skipped.'}
          </p>
          <div className="mt-4 h-1.5 rounded-full bg-surface-variant overflow-hidden">
            <div
              className="h-full rounded-full gradient-accent transition-[width] duration-500"
              style={{ width: `${Math.max(2, value)}%` }}
            />
          </div>
        </div>
      </div>
    </SurfaceCard>
  );
}

// ── Scalar sections ─────────────────────────────────────────────────────────

/** A card of profile columns saved together. */
function ScalarSection({ icon, title, subtitle, profile, institutionId, onSaved, children, build }) {
  const [form, setForm] = useState(() => build.initial(profile ?? {}));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [saved, setSaved] = useState(false);

  const set = (key) => (event) => {
    setSaved(false);
    setForm((prev) => ({ ...prev, [key]: event.target.value }));
  };

  async function save(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error: writeError } = await supabase
      .from('institution_profiles')
      .update(build.payload(form))
      .eq('institution_id', institutionId);

    setBusy(false);
    if (writeError) {
      setError(describeError(writeError));
      return;
    }
    setSaved(true);
    onSaved();
  }

  return (
    <SurfaceCard className="p-6">
      <form onSubmit={save}>
        <CardHeader icon={icon} title={title} subtitle={subtitle} />
        {error && <div className="mt-4"><Alert tone="error">{error}</Alert></div>}
        {saved && <div className="mt-4"><Alert tone="success">Saved.</Alert></div>}
        <div className="mt-5 flex flex-col gap-4">
          {children({ form, set })}
          <Button type="submit" loading={busy} icon={Save} className="w-fit">
            Save
          </Button>
        </div>
      </form>
    </SurfaceCard>
  );
}

const text = (v) => (v === '' || v === undefined ? null : v);
const num = (v) => (v === '' || v === null || v === undefined ? null : Number(v));

function AboutSection(props) {
  return (
    <ScalarSection
      {...props}
      icon={BookOpen}
      title="About"
      subtitle="What this place is, and what it is like to be there."
      build={{
        initial: (p) => ({
          tagline: p.tagline ?? '',
          about: p.about ?? '',
          campus_life: p.campus_life ?? '',
          accommodation: p.accommodation ?? '',
          founded_year: p.founded_year ?? '',
          student_count: p.student_count ?? '',
          international_student_count: p.international_student_count ?? '',
        }),
        payload: (f) => ({
          tagline: text(f.tagline),
          about: text(f.about),
          campus_life: text(f.campus_life),
          accommodation: text(f.accommodation),
          founded_year: num(f.founded_year),
          student_count: num(f.student_count),
          international_student_count: num(f.international_student_count),
        }),
      }}
    >
      {({ form, set }) => (
        <>
          <Field label="Tagline" hint="One line, shown under your name.">
            <Input value={form.tagline} onChange={set('tagline')}
              placeholder="Where ambition meets opportunity" />
          </Field>
          <Field label="About">
            <Textarea rows={5} value={form.about} onChange={set('about')} />
          </Field>
          <Field label="Campus life">
            <Textarea rows={4} value={form.campus_life} onChange={set('campus_life')}
              placeholder="Clubs, sport, the city, what a week actually looks like." />
          </Field>
          <Field
            label="Accommodation"
            hint="Where a student will live in their first year is one of the two questions every parent asks."
          >
            <Textarea rows={4} value={form.accommodation} onChange={set('accommodation')} />
          </Field>
          <div className="grid grid-cols-3 gap-4">
            <Field label="Founded">
              <Input type="number" value={form.founded_year} onChange={set('founded_year')} />
            </Field>
            <Field label="Students">
              <Input type="number" value={form.student_count} onChange={set('student_count')} />
            </Field>
            <Field label="International students">
              <Input type="number" value={form.international_student_count}
                onChange={set('international_student_count')} />
            </Field>
          </div>
        </>
      )}
    </ScalarSection>
  );
}

function CostSection(props) {
  return (
    <ScalarSection
      {...props}
      icon={Wallet}
      title="Cost"
      subtitle="Living costs and fees. Tuition belongs to each program."
      build={{
        initial: (p) => ({
          cost_of_living_min: p.cost_of_living_min ?? '',
          cost_of_living_max: p.cost_of_living_max ?? '',
          cost_currency: p.cost_currency ?? 'USD',
          application_fee: p.application_fee ?? '',
          deposit: p.deposit ?? '',
          fee_currency: p.fee_currency ?? 'USD',
        }),
        payload: (f) => ({
          cost_of_living_min: num(f.cost_of_living_min),
          cost_of_living_max: num(f.cost_of_living_max),
          cost_currency: f.cost_currency,
          application_fee: num(f.application_fee),
          deposit: num(f.deposit),
          fee_currency: f.fee_currency,
        }),
      }}
    >
      {({ form, set }) => (
        <>
          <div className="grid grid-cols-3 gap-4">
            <Field label="Currency">
              <Select value={form.cost_currency} onChange={set('cost_currency')}>
                {['USD', 'GBP', 'EUR', 'CAD', 'AUD'].map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </Select>
            </Field>
            <Field label="Living costs from" hint="Per year.">
              <Input type="number" value={form.cost_of_living_min}
                onChange={set('cost_of_living_min')} placeholder="12000" />
            </Field>
            <Field label="Living costs to">
              <Input type="number" value={form.cost_of_living_max}
                onChange={set('cost_of_living_max')} placeholder="18000" />
            </Field>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Field label="Fee currency">
              <Select value={form.fee_currency} onChange={set('fee_currency')}>
                {['USD', 'GBP', 'EUR', 'CAD', 'AUD'].map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </Select>
            </Field>
            <Field label="Application fee">
              <Input type="number" value={form.application_fee}
                onChange={set('application_fee')} />
            </Field>
            <Field label="Deposit">
              <Input type="number" value={form.deposit} onChange={set('deposit')} />
            </Field>
          </div>
        </>
      )}
    </ScalarSection>
  );
}

function CredibilitySection(props) {
  return (
    <ScalarSection
      {...props}
      icon={GraduationCap}
      title="Credibility and how to apply"
      subtitle="Accreditation, rankings, and the steps a student takes."
      build={{
        initial: (p) => ({
          accreditation: (p.accreditation ?? []).join(', '),
          rankings: (p.rankings ?? [])
            .map((r) => `${r.body} | ${r.rank} | ${r.year ?? ''}`).join('\n'),
          application_steps: (p.application_steps ?? [])
            .map((s) => `${s.title}${s.detail ? ` | ${s.detail}` : ''}`).join('\n'),
          socials: Object.entries(p.socials ?? {})
            .map(([k, v]) => `${k} | ${v}`).join('\n'),
        }),
        payload: (f) => ({
          accreditation: f.accreditation
            .split(',').map((s) => s.trim()).filter(Boolean),
          // Edited as lines because these are short, ordered and always
          // rewritten as a block — a row editor would be more UI than value.
          rankings: f.rankings.split('\n').map((line) => {
            const [body, rank, year] = line.split('|').map((s) => s.trim());
            return body ? { body, rank: Number(rank) || null, year: Number(year) || null } : null;
          }).filter(Boolean),
          application_steps: f.application_steps.split('\n').map((line) => {
            const [title, detail] = line.split('|').map((s) => s.trim());
            return title ? { title, detail: detail || null } : null;
          }).filter(Boolean),
          socials: Object.fromEntries(
            f.socials.split('\n').map((line) => {
              const [key, url] = line.split('|').map((s) => s.trim());
              return key && url ? [key, url] : null;
            }).filter(Boolean),
          ),
        }),
      }}
    >
      {({ form, set }) => (
        <>
          <Field label="Accreditation" hint="Comma separated.">
            <Input value={form.accreditation} onChange={set('accreditation')}
              placeholder="Universities Canada, AACSB" />
          </Field>
          <Field label="Rankings" hint="One per line: body | rank | year">
            <Textarea rows={3} value={form.rankings} onChange={set('rankings')}
              placeholder={'QS World | 301 | 2026\nMaclean\'s | 12 | 2025'} />
          </Field>
          <Field label="How to apply" hint="One step per line: title | detail">
            <Textarea rows={4} value={form.application_steps}
              onChange={set('application_steps')}
              placeholder={'Submit your transcript | Certified copy, in English\nPay the application fee'} />
          </Field>
          <Field label="Social links" hint="One per line: name | url">
            <Textarea rows={3} value={form.socials} onChange={set('socials')}
              placeholder={'instagram | https://instagram.com/…\nyoutube | https://youtube.com/…'} />
          </Field>
        </>
      )}
    </ScalarSection>
  );
}

// ── Repeating sections ──────────────────────────────────────────────────────

/**
 * A table plus an add/edit dialog, driven by a field spec.
 *
 * Six of these sections are the same shape — list rows, add one, edit one,
 * delete one — so they share a component rather than six near-identical pages.
 */
function ListSection({
  icon, title, subtitle, table, institutionId, columns, fields, upload, order = 'ord',
}) {
  const [editing, setEditing] = useState(null);
  const [actionError, setActionError] = useState(null);

  const { data: rows, loading, reload } = useQuery(
    (client) =>
      client.from(table).select('*').eq('institution_id', institutionId).order(order),
    [institutionId, table],
  );

  async function remove(row) {
    setActionError(null);
    const { error } = await supabase.from(table).delete().eq('id', row.id);
    if (error) setActionError(describeError(error));
    else reload();
  }

  return (
    <SurfaceCard className="p-6">
      <CardHeader
        icon={icon}
        title={title}
        subtitle={subtitle}
        action={
          <Button size="sm" icon={Plus} onClick={() => setEditing({})}>
            Add
          </Button>
        }
      />

      {actionError && <div className="mt-4"><Alert tone="error">{actionError}</Alert></div>}

      <div className="mt-5">
        {loading ? (
          <Loading />
        ) : (rows ?? []).length === 0 ? (
          <p className="text-[13px] text-subtle py-4">Nothing added yet.</p>
        ) : (
          <div className="flex flex-col gap-1.5">
            {rows.map((row) => (
              <div
                key={row.id}
                className="flex items-center gap-4 px-3.5 py-2.5 rounded-tile bg-surface-variant"
              >
                {columns.map((col) => (
                  <div key={col.key} className="min-w-0 flex-1 text-[13px] truncate">
                    <span className="text-subtle text-[11px] uppercase tracking-[0.5px] block">
                      {col.label}
                    </span>
                    {col.render ? col.render(row) : (row[col.key] ?? '—')}
                  </div>
                ))}
                <Button size="sm" variant="ghost" onClick={() => setEditing(row)}>
                  Edit
                </Button>
                <Button
                  size="sm"
                  variant="dangerGhost"
                  icon={Trash2}
                  onClick={() => remove(row)}
                  title="Remove"
                />
              </div>
            ))}
          </div>
        )}
      </div>

      {editing && (
        <RowDialog
          title={title}
          table={table}
          institutionId={institutionId}
          fields={fields}
          upload={upload}
          row={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            reload();
          }}
        />
      )}
    </SurfaceCard>
  );
}

function RowDialog({ title, table, institutionId, fields, upload, row, onClose, onSaved }) {
  const isNew = !row.id;
  const [form, setForm] = useState(() =>
    Object.fromEntries(fields.map((f) => [f.key, row[f.key] ?? f.default ?? ''])),
  );
  const [file, setFile] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const set = (key) => (event) =>
    setForm((prev) => ({ ...prev, [key]: event.target.value }));

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const payload = { institution_id: institutionId };
    for (const field of fields) {
      const value = form[field.key];
      payload[field.key] =
        value === '' ? null : field.type === 'number' ? Number(value) : value;
    }

    // Uploaded under the institution's uuid, which is what the storage policy
    // and the CHECK on storage_path both authorize on.
    if (upload && file) {
      const path = `${institutionId}/${Date.now()}-${file.name.replace(/[^\w.-]/g, '_')}`;
      const { error: uploadError } = await supabase.storage
        .from(upload.bucket)
        .upload(path, file, { contentType: file.type });

      if (uploadError) {
        setBusy(false);
        setError(describeError(uploadError));
        return;
      }
      payload[upload.column] = path;
    }

    const { error: writeError } = isNew
      ? await supabase.from(table).insert(payload)
      : await supabase.from(table).update(payload).eq('id', row.id);

    setBusy(false);
    if (writeError) {
      setError(describeError(writeError));
      return;
    }
    onSaved();
  }

  return (
    <Dialog
      as="form"
      title={isNew ? `Add to ${title.toLowerCase()}` : `Edit ${title.toLowerCase()}`}
      onClose={onClose}
      onSubmit={handleSubmit}
      width="max-w-[620px]"
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={busy}>{isNew ? 'Add' : 'Save'}</Button>
        </>
      }
    >
      {error && <div className="mb-5"><Alert tone="error">{error}</Alert></div>}

      <div className="flex flex-col gap-4">
        {upload && (
          <Field label="File" hint="JPG, PNG or PDF, up to 10 MB.">
            <input
              type="file"
              accept="image/*,application/pdf"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              className="w-full text-[13px] text-muted file:mr-3 file:px-4 file:h-9 file:rounded-full file:border-0 file:bg-accent/15 file:text-accent file:font-semibold file:cursor-pointer"
            />
          </Field>
        )}

        {fields.map((field) => (
          <Field key={field.key} label={field.label} hint={field.hint}>
            {field.type === 'textarea' ? (
              <Textarea rows={3} value={form[field.key]} onChange={set(field.key)}
                placeholder={field.placeholder} />
            ) : field.type === 'select' ? (
              <Select value={form[field.key]} onChange={set(field.key)}>
                {field.allowEmpty && <option value="">{field.allowEmpty}</option>}
                {Object.entries(field.options).map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </Select>
            ) : (
              <Input
                type={field.type ?? 'text'}
                step={field.step}
                value={form[field.key]}
                onChange={set(field.key)}
                placeholder={field.placeholder}
                required={field.required}
              />
            )}
          </Field>
        ))}
      </div>
    </Dialog>
  );
}
