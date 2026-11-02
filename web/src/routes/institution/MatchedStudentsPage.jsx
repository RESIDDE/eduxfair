import { useMemo, useState } from 'react';
import { Check, Eye, Lock, Send, Sparkles, X } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Dialog,
  EmptyState,
  Field,
  Loading,
  Select,
  SurfaceCard,
  Textarea,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useFieldLabels, useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { countryName, STUDY_LEVELS } from '../../lib/vocab';

/**
 * Reverse admission, from the institution's side.
 *
 * Students here are PSEUDONYMOUS. `matched_student_cards` exposes country,
 * level, field, grade band, age band, budget band and the match score — and
 * deliberately not name, contact details, date of birth, exact grades or
 * documents.
 *
 * The key is a per-institution `token`, not an account id. Two institutions
 * looking at the same student see unrelated tokens, and the mapping back to a
 * person lives in a table with no RLS policies at all — so a token cannot be
 * joined against the public social directory either. Every action goes through
 * a SECURITY DEFINER function that resolves the token server-side.
 *
 * That is not a limitation to work around: it is what makes it reasonable to
 * show an institution a list of minors' academic profiles at all.
 */
export default function MatchedStudentsPage() {
  const { institutionId } = useAuth();
  const fieldLabels = useFieldLabels();

  const [programFilter, setProgramFilter] = useState('');
  const [minScore, setMinScore] = useState(40);
  const [inviting, setInviting] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [notice, setNotice] = useState(null);

  const { data: programs } = useQuery(
    (client) =>
      client
        .from('programs')
        .select('id, name, level')
        .eq('institution_id', institutionId)
        .eq('is_active', true)
        .order('name'),
    [institutionId],
  );

  const { data: cards, loading, error, reload } = useQuery(
    (client) => {
      let query = client
        .from('matched_student_cards')
        .select('*')
        .eq('institution_id', institutionId)
        .gte('score', minScore)
        .order('score', { ascending: false })
        .limit(200);
      if (programFilter) query = query.eq('program_id', programFilter);
      return query;
    },
    [institutionId, programFilter, minScore],
  );

  const grouped = useMemo(() => {
    // One student can match several programs; show them once with their best
    // match, so the list is a list of people rather than of rows. The token is
    // stable per student per institution, so it groups correctly.
    const byStudent = new Map();
    for (const card of cards ?? []) {
      const existing = byStudent.get(card.token);
      if (!existing || card.score > existing.score) byStudent.set(card.token, card);
    }
    return [...byStudent.values()].sort((a, b) => b.score - a.score);
  }, [cards]);

  /**
   * Shortlist, pass or invite.
   *
   * Through an RPC rather than a direct insert: `institution_interests` rows
   * carry the student's account id, which is the thing the token withholds, so
   * this console has no write access to that table at all.
   */
  async function act(card, kind, note) {
    setActionError(null);

    const { error: writeError } =
      kind === 'invited'
        ? await supabase.rpc('institution_invite_student', {
            p_token: card.token,
            p_program_id: card.program_id,
            p_note: note || null,
          })
        : await supabase.rpc('institution_record_interest', {
            p_token: card.token,
            p_program_id: card.program_id,
            p_kind: kind,
            p_note: note || null,
          });

    if (writeError) {
      setActionError(describeError(writeError));
      return false;
    }
    reload();
    return true;
  }

  /** Asks the student to share their passport. They decide; this only asks. */
  async function requestAccess(card) {
    setActionError(null);
    const { error: writeError } = await supabase.rpc('institution_request_access', {
      p_token: card.token,
      p_note: null,
    });

    if (writeError) {
      setActionError(describeError(writeError));
      return;
    }
    setNotice('Asked. You will see their details if they agree to share.');
  }

  if (loading) return <Loading label="Finding students who match you" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  return (
    <div className="flex flex-col gap-5 pb-4">
      <SurfaceCard className="p-4">
        <div className="flex items-start gap-3">
          <Lock size={17} className="text-accent mt-0.5 shrink-0" strokeWidth={2.2} />
          <p className="text-[13px] text-muted leading-relaxed">
            These profiles are anonymous by design. You can invite a student
            before you know who they are — if they accept, they share their
            passport and you see their name, contact details and documents.
          </p>
        </div>
      </SurfaceCard>

      {actionError && <Alert tone="error">{actionError}</Alert>}
      {notice && <Alert tone="success">{notice}</Alert>}

      <div className="flex flex-wrap items-end gap-4">
        <Field label="Program" className="w-[260px]">
          <Select
            value={programFilter}
            onChange={(e) => setProgramFilter(e.target.value)}
          >
            <option value="">All programs</option>
            {(programs ?? []).map((program) => (
              <option key={program.id} value={program.id}>
                {program.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Minimum match" className="w-[180px]">
          <Select value={minScore} onChange={(e) => setMinScore(Number(e.target.value))}>
            <option value={40}>40% and above</option>
            <option value={55}>55% and above</option>
            <option value={70}>70% and above</option>
            <option value={85}>85% and above</option>
          </Select>
        </Field>
        <div className="ml-auto text-[13px] text-subtle pb-3">
          {grouped.length} student{grouped.length === 1 ? '' : 's'}
        </div>
      </div>

      {grouped.length === 0 ? (
        <EmptyState
          icon={Sparkles}
          title="No matches yet"
          subtitle={
            (programs ?? []).length === 0
              ? 'Add a program first — matching needs something to match against.'
              : 'No students currently meet this threshold. Lowering the minimum match, or widening a program’s entry requirements, usually surfaces more.'
          }
        />
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3 gap-4">
          {grouped.map((card) => (
            <StudentCard
              key={card.token}
              card={card}
              fieldLabels={fieldLabels}
              onInvite={() => setInviting(card)}
              onShortlist={() => act(card, 'shortlisted')}
              onPass={() => act(card, 'passed')}
              onRequestAccess={() => requestAccess(card)}
            />
          ))}
        </div>
      )}

      {inviting && (
        <InviteDialog
          card={inviting}
          onClose={() => setInviting(null)}
          onSend={async (note) => {
            const ok = await act(inviting, 'invited', note);
            if (ok) setInviting(null);
          }}
        />
      )}
    </div>
  );
}

function StudentCard({
  card,
  fieldLabels,
  onInvite,
  onShortlist,
  onPass,
  onRequestAccess,
}) {
  const tone =
    card.score >= 85 ? 'success' : card.score >= 70 ? 'live' : 'info';
  const strength =
    card.score >= 85
      ? 'Excellent match'
      : card.score >= 70
        ? 'Strong match'
        : card.score >= 55
          ? 'Good match'
          : 'Possible match';

  return (
    <SurfaceCard className="p-5 flex flex-col">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <Badge tone={tone} compact>
              {card.score}% · {strength}
            </Badge>
            {card.passport_verification === 'verified' && (
              <Badge tone="success" compact>
                Verified
              </Badge>
            )}
          </div>
          <div className="mt-2.5 font-semibold truncate">{card.program_name}</div>
        </div>
        {card.already_actioned && (
          <span title="You have already actioned this student">
            <Check size={16} className="text-success shrink-0" strokeWidth={2.6} />
          </span>
        )}
      </div>

      <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2.5 text-[12.5px]">
        <Pair label="In" value={countryName(card.current_country)} />
        <Pair label="From" value={countryName(card.nationality)} />
        <Pair label="Age" value={card.age_band} />
        <Pair label="Grades" value={card.grade_band} />
        <Pair
          label="English"
          value={card.english_band ? `IELTS ${Number(card.english_band).toFixed(1)}` : null}
        />
        <Pair label="Budget" value={card.budget_band} />
        <Pair label="Intake" value={card.intended_intake} />
        <Pair
          label="Seeking"
          value={(card.target_levels ?? [])
            .map((l) => STUDY_LEVELS[l] ?? l)
            .join(', ')}
        />
      </dl>

      {(card.target_fields ?? []).length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {card.target_fields.map((slug) => (
            <span
              key={slug}
              className="px-2 py-0.5 rounded-md bg-surface-variant text-[11.5px] text-muted"
            >
              {fieldLabels[slug] ?? slug}
            </span>
          ))}
        </div>
      )}

      {(card.reasons ?? []).length > 0 && (
        <details className="mt-4 group">
          <summary className="text-[12.5px] text-accent font-semibold cursor-pointer list-none">
            Why they matched →
          </summary>
          <ul className="mt-2.5 flex flex-col gap-1.5">
            {card.reasons.map((reason, i) => (
              <li key={i} className="flex items-start gap-2 text-[12.5px] text-muted">
                <Check size={13} className="text-success mt-0.5 shrink-0" strokeWidth={2.6} />
                {reason.detail}
              </li>
            ))}
          </ul>
        </details>
      )}

      <div className="mt-auto pt-5 flex items-center gap-2">
        {card.is_shared ? (
          <Badge tone="success" compact>
            <Eye size={11} strokeWidth={2.6} /> {card.shared_name ?? 'Passport shared'}
          </Badge>
        ) : (
          <>
            <Button size="sm" icon={Send} onClick={onInvite} className="flex-1">
              Invite
            </Button>
            <Button
              size="sm"
              variant="outline"
              icon={Eye}
              onClick={onRequestAccess}
              title="Ask them to share their passport"
            />
          </>
        )}
        <Button size="sm" variant="outline" onClick={onShortlist}>
          Shortlist
        </Button>
        <Button size="sm" variant="ghost" icon={X} onClick={onPass} title="Pass" />
      </div>
    </SurfaceCard>
  );
}

function Pair({ label, value }) {
  return (
    <div className="min-w-0">
      <dt className="text-subtle text-[11px] uppercase tracking-[0.6px]">{label}</dt>
      <dd className="truncate font-medium">{value || '—'}</dd>
    </div>
  );
}

function InviteDialog({ card, onClose, onSend }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  return (
    <Dialog
      as="form"
      title="Invite this student"
      eyebrow={`${card.score}% match · ${card.program_name}`}
      onClose={onClose}
      onSubmit={async (event) => {
        event.preventDefault();
        setBusy(true);
        await onSend(note);
        setBusy(false);
      }}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} type="button">
            Cancel
          </Button>
          <Button type="submit" loading={busy} icon={Send}>
            Send invitation
          </Button>
        </>
      }
    >
      <p className="text-muted leading-relaxed">
        The student will see that you want to hear from them, along with your
        note. They decide whether to share their passport — until they do, you
        will not see their name or documents.
      </p>
      <div className="mt-5">
        <Field
          label="Your note"
          hint="Students respond far more often when this says something specific."
        >
          <Textarea
            rows={4}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Your profile is a strong fit for our co-op stream, and we have scholarships for the Fall 2026 intake."
          />
        </Field>
      </div>
    </Dialog>
  );
}
