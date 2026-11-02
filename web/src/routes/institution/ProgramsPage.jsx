import { useState } from 'react';
import { GraduationCap, Pencil, Plus } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Dialog,
  EmptyRow,
  EmptyState,
  Field,
  Input,
  Loading,
  Select,
  TableCard,
  Td,
  Th,
  Toolbar,
  Tr,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useFieldsOfStudy, useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { tuitionRange } from '../../lib/format';
import { GRADING_SCHEMES, STUDY_LEVELS } from '../../lib/vocab';

/**
 * Programs CRUD.
 *
 * Every save re-runs matching for that program via a database trigger, so a
 * widened entry requirement surfaces new students immediately — nothing here
 * has to ask for a recompute.
 */
export default function ProgramsPage() {
  const { institutionId } = useAuth();
  const { fields } = useFieldsOfStudy();
  const [editing, setEditing] = useState(null);

  const { data: programs, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('programs')
        .select('*')
        .eq('institution_id', institutionId)
        .order('is_active', { ascending: false })
        .order('name'),
    [institutionId],
  );

  if (loading) return <Loading label="Loading your programs" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const fieldLabels = Object.fromEntries(fields.map((f) => [f.slug, f.label]));

  return (
    <div className="flex flex-col gap-4 h-full">
      <Toolbar summary={`${(programs ?? []).length} program${(programs ?? []).length === 1 ? '' : 's'}`}>
        <Button icon={Plus} onClick={() => setEditing({})}>
          Add program
        </Button>
      </Toolbar>

      {(programs ?? []).length === 0 ? (
        <EmptyState
          icon={GraduationCap}
          title="No programs yet"
          subtitle="Matching needs something to match against. Add your first program and students will start appearing."
          action={
            <Button icon={Plus} onClick={() => setEditing({})}>
              Add program
            </Button>
          }
        />
      ) : (
        <TableCard minWidth={960}>
          <thead>
            <tr>
              <Th>Program</Th>
              <Th>Level</Th>
              <Th>Field</Th>
              <Th>Tuition</Th>
              <Th>Entry</Th>
              <Th>Intakes</Th>
              <Th>Status</Th>
              <Th />
            </tr>
          </thead>
          <tbody>
            {programs.map((program) => (
              <Tr key={program.id}>
                <Td className="font-semibold">{program.name}</Td>
                <Td>{STUDY_LEVELS[program.level] ?? program.level}</Td>
                <Td>{fieldLabels[program.field_of_study] ?? program.field_of_study}</Td>
                <Td className="tabular-nums">{tuitionRange(program)}</Td>
                <Td>
                  {program.min_grade_value == null
                    ? '—'
                    : `${program.min_grade_value} (${
                        GRADING_SCHEMES[program.min_grade_scheme] ?? ''
                      })`}
                </Td>
                <Td>{(program.intakes ?? []).join(', ') || '—'}</Td>
                <Td>
                  {program.is_active ? (
                    <Badge tone="success" compact>
                      Live
                    </Badge>
                  ) : (
                    <Badge tone="neutral" compact>
                      Draft
                    </Badge>
                  )}
                </Td>
                <Td>
                  <Button
                    size="sm"
                    variant="ghost"
                    icon={Pencil}
                    onClick={() => setEditing(program)}
                    title="Edit"
                  />
                </Td>
              </Tr>
            ))}
            {programs.length === 0 && <EmptyRow colSpan={8}>No programs</EmptyRow>}
          </tbody>
        </TableCard>
      )}

      {editing && (
        <ProgramDialog
          program={editing}
          fields={fields}
          institutionId={institutionId}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

function ProgramDialog({ program, fields, institutionId, onClose, onSaved }) {
  const isNew = !program.id;

  const [form, setForm] = useState({
    name: program.name ?? '',
    level: program.level ?? 'undergraduate',
    field_of_study: program.field_of_study ?? '',
    tuition_min: program.tuition_min ?? '',
    tuition_max: program.tuition_max ?? '',
    tuition_currency: program.tuition_currency ?? 'USD',
    duration_months: program.duration_months ?? '',
    intakes: (program.intakes ?? []).join(', '),
    min_grade_value: program.min_grade_value ?? '',
    min_grade_scheme: program.min_grade_scheme ?? '',
    min_english_band: program.min_english_band ?? '',
    scholarship_available: program.scholarship_available ?? false,
    is_active: program.is_active ?? true,
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const set = (key) => (event) => {
    const value =
      event.target.type === 'checkbox' ? event.target.checked : event.target.value;
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  async function handleSubmit(event) {
    event.preventDefault();

    // The CHECK constraint requires both or neither — a grade with no scheme is
    // meaningless and would be rejected by the database anyway.
    if ((form.min_grade_value === '') !== (form.min_grade_scheme === '')) {
      setError('Enter both a minimum grade and the scheme it is in, or neither.');
      return;
    }

    setBusy(true);
    setError(null);

    const payload = {
      institution_id: institutionId,
      name: form.name.trim(),
      level: form.level,
      field_of_study: form.field_of_study,
      tuition_min: form.tuition_min === '' ? null : Number(form.tuition_min),
      tuition_max: form.tuition_max === '' ? null : Number(form.tuition_max),
      tuition_currency: form.tuition_currency,
      duration_months:
        form.duration_months === '' ? null : Number(form.duration_months),
      intakes: form.intakes
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
      min_grade_value:
        form.min_grade_value === '' ? null : Number(form.min_grade_value),
      min_grade_scheme: form.min_grade_scheme || null,
      min_english_band:
        form.min_english_band === '' ? null : Number(form.min_english_band),
      scholarship_available: form.scholarship_available,
      is_active: form.is_active,
    };

    const { error: writeError } = isNew
      ? await supabase.from('programs').insert(payload)
      : await supabase.from('programs').update(payload).eq('id', program.id);

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
      title={isNew ? 'Add a program' : 'Edit program'}
      onClose={onClose}
      onSubmit={handleSubmit}
      width="max-w-[680px]"
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            {isNew ? 'Add program' : 'Save changes'}
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      <div className="flex flex-col gap-4">
        <Field label="Program name">
          <Input
            value={form.name}
            onChange={set('name')}
            placeholder="BSc Computer Science"
            required
          />
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field label="Level">
            <Select value={form.level} onChange={set('level')} required>
              {Object.entries(STUDY_LEVELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          <Field
            label="Field of study"
            hint="Students pick from this same list — it is how matching connects you."
          >
            <Select value={form.field_of_study} onChange={set('field_of_study')} required>
              <option value="">Choose…</option>
              {fields.map((field) => (
                <option key={field.slug} value={field.slug}>
                  {field.label}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <div className="grid grid-cols-4 gap-4">
          <Field label="Currency">
            <Select value={form.tuition_currency} onChange={set('tuition_currency')}>
              {['USD', 'GBP', 'EUR', 'CAD', 'AUD'].map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Tuition from">
            <Input
              type="number"
              min="0"
              value={form.tuition_min}
              onChange={set('tuition_min')}
              placeholder="18000"
            />
          </Field>
          <Field label="Tuition to">
            <Input
              type="number"
              min="0"
              value={form.tuition_max}
              onChange={set('tuition_max')}
              placeholder="24000"
            />
          </Field>
          <Field label="Months">
            <Input
              type="number"
              min="1"
              value={form.duration_months}
              onChange={set('duration_months')}
              placeholder="48"
            />
          </Field>
        </div>

        <Field label="Intakes" hint="Comma separated, e.g. Fall 2026, Winter 2027">
          <Input
            value={form.intakes}
            onChange={set('intakes')}
            placeholder="Fall 2026, Winter 2027"
          />
        </Field>

        <div className="grid grid-cols-3 gap-4">
          <Field label="Minimum grade">
            <Input
              type="number"
              step="0.1"
              value={form.min_grade_value}
              onChange={set('min_grade_value')}
              placeholder="65"
            />
          </Field>
          <Field label="In which scheme">
            <Select value={form.min_grade_scheme} onChange={set('min_grade_scheme')}>
              <option value="">Not specified</option>
              {Object.entries(GRADING_SCHEMES).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="English (IELTS)" hint="Or equivalent">
            <Input
              type="number"
              step="0.5"
              min="0"
              max="9"
              value={form.min_english_band}
              onChange={set('min_english_band')}
              placeholder="6.5"
            />
          </Field>
        </div>

        <p className="text-[12.5px] text-subtle leading-relaxed">
          Grades are converted across systems so a WAEC result and a GPA can both
          be compared against your minimum. Leaving a requirement blank does not
          penalise students — it just means we cannot check it, and you assess it
          yourself.
        </p>

        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={form.scholarship_available}
            onChange={set('scholarship_available')}
            className="size-4 accent-accent"
          />
          <span className="text-[13.5px]">Scholarships available</span>
        </label>

        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={form.is_active}
            onChange={set('is_active')}
            className="size-4 accent-accent"
          />
          <span className="text-[13.5px]">
            Live — visible to students and included in matching
          </span>
        </label>
      </div>
    </Dialog>
  );
}
