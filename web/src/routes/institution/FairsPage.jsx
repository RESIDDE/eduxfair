import { useState } from 'react';
import { QrCode, ScanLine, UserCheck } from 'lucide-react';
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
  StatsStrip,
  SurfaceCard,
  TableCard,
  Td,
  Textarea,
  Th,
  Tr,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDate, formatDateTime, initials } from '../../lib/format';

/**
 * Booth scanning and leads at a Lekkside fair.
 *
 * The scan goes through `record_booth_visit()`, not a direct insert: that
 * function validates the pass code, checks the caller actually staffs the
 * booth, writes the visit and grants the passport share in one transaction.
 * There is no insert policy on `booth_visits` at all, so there is no other way
 * to record one.
 */
export default function FairsPage() {
  const { institutionId } = useAuth();
  const [scanning, setScanning] = useState(null);

  const { data: exhibitors, loading, error } = useQuery(
    (client) =>
      client
        .from('fair_exhibitors')
        .select('id, booth_code, booth_label, package, fair_id, fairs!inner(*)')
        .eq('institution_id', institutionId)
        .order('created_at', { ascending: false }),
    [institutionId],
  );

  const { data: visits, reload: reloadVisits } = useQuery(
    (client) =>
      client
        .from('booth_visits')
        .select(
          'id, interest_level, follow_up_requested, scholarship_discussed, ' +
            'program_interest, note, created_at, exhibitor_id, ' +
            'student:profiles!profile_id(id, full_name, country), programs(id, name)',
        )
        .order('created_at', { ascending: false })
        .limit(300),
    [institutionId],
  );

  if (loading) return <Loading label="Loading your fairs" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = exhibitors ?? [];

  if (rows.length === 0) {
    return (
      <EmptyState
        icon={QrCode}
        title="Not exhibiting yet"
        subtitle="Eduxfair adds your booth when you book a fair. Once you have a booth code, you can scan student Fair Passports from here."
      />
    );
  }

  const allVisits = visits ?? [];

  return (
    <div className="flex flex-col gap-6 pb-4">
      {rows.map((exhibitor) => {
        const boothVisits = allVisits.filter((v) => v.exhibitor_id === exhibitor.id);
        const followUps = boothVisits.filter((v) => v.follow_up_requested);
        const scholarships = boothVisits.filter((v) => v.scholarship_discussed);

        return (
          <div key={exhibitor.id} className="flex flex-col gap-4">
            <SurfaceCard className="p-6">
              <div className="flex items-start justify-between gap-4 flex-wrap">
                <div className="min-w-0">
                  <h2 className="font-bold text-[17px]">{exhibitor.fairs?.name}</h2>
                  <div className="mt-1 text-[13px] text-muted">
                    {[exhibitor.fairs?.venue, exhibitor.fairs?.city]
                      .filter(Boolean)
                      .join(', ')}{' '}
                    · {formatDate(exhibitor.fairs?.starts_at)}
                  </div>
                  <div className="mt-3 flex items-center gap-2 flex-wrap">
                    <Badge tone="live" compact>
                      Booth {exhibitor.booth_code}
                    </Badge>
                    <Badge tone="neutral" compact>
                      {exhibitor.package.replace(/_/g, ' ')}
                    </Badge>
                  </div>
                </div>
                <Button icon={ScanLine} onClick={() => setScanning(exhibitor)}>
                  Scan a pass
                </Button>
              </div>
            </SurfaceCard>

            <StatsStrip
              items={[
                { label: 'Students met', value: boothVisits.length },
                {
                  label: 'Follow-ups requested',
                  value: followUps.length,
                  tone: followUps.length > 0 ? 'text-accent' : undefined,
                },
                {
                  label: 'Scholarship talks',
                  value: scholarships.length,
                  tone: scholarships.length > 0 ? 'text-warning' : undefined,
                },
                {
                  label: 'High interest',
                  value: boothVisits.filter((v) => v.interest_level === 'high').length,
                  tone: 'text-success',
                },
              ]}
            />

            <TableCard minWidth={820}>
              <thead>
                <tr>
                  <Th>Student</Th>
                  <Th>Interest in</Th>
                  <Th>Level</Th>
                  <Th>Follow-up</Th>
                  <Th>Scholarship</Th>
                  <Th>Met</Th>
                </tr>
              </thead>
              <tbody>
                {boothVisits.map((visit) => (
                  <Tr key={visit.id}>
                    <Td>
                      <div className="flex items-center gap-2.5">
                        <div className="size-7 rounded-full bg-surface-variant grid place-items-center text-[10.5px] font-bold shrink-0">
                          {initials(visit.student?.full_name) || '?'}
                        </div>
                        <span className="font-semibold">
                          {visit.student?.full_name || 'Student'}
                        </span>
                      </div>
                    </Td>
                    <Td>{visit.programs?.name ?? visit.program_interest ?? '—'}</Td>
                    <Td>
                      <Badge
                        tone={
                          visit.interest_level === 'high'
                            ? 'success'
                            : visit.interest_level === 'medium'
                              ? 'info'
                              : 'neutral'
                        }
                        compact
                      >
                        {visit.interest_level}
                      </Badge>
                    </Td>
                    <Td>{visit.follow_up_requested ? 'Yes' : '—'}</Td>
                    <Td>{visit.scholarship_discussed ? 'Yes' : '—'}</Td>
                    <Td>{formatDateTime(visit.created_at)}</Td>
                  </Tr>
                ))}
                {boothVisits.length === 0 && (
                  <EmptyRow colSpan={6} icon={UserCheck}>
                    No one scanned yet
                  </EmptyRow>
                )}
              </tbody>
            </TableCard>
          </div>
        );
      })}

      {scanning && (
        <ScanDialog
          exhibitor={scanning}
          institutionId={institutionId}
          onClose={() => setScanning(null)}
          onScanned={() => {
            reloadVisits();
          }}
        />
      )}
    </div>
  );
}

function ScanDialog({ exhibitor, institutionId, onClose, onScanned }) {
  const [passCode, setPassCode] = useState('');
  const [programId, setProgramId] = useState('');
  const [interest, setInterest] = useState('medium');
  const [followUp, setFollowUp] = useState(true);
  const [scholarship, setScholarship] = useState(false);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);

  const { data: programs } = useQuery(
    (client) =>
      client
        .from('programs')
        .select('id, name')
        .eq('institution_id', institutionId)
        .eq('is_active', true)
        .order('name'),
    [institutionId],
  );

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setSuccess(null);

    const { error: rpcError } = await supabase.rpc('record_booth_visit', {
      p_pass_code: passCode.trim().toUpperCase().replace(/\s/g, ''),
      p_booth_code: exhibitor.booth_code,
      p_program_id: programId || null,
      p_program_interest: null,
      p_interest_level: interest,
      p_follow_up_requested: followUp,
      p_scholarship_discussed: scholarship,
      p_note: note || null,
    });

    setBusy(false);

    if (rpcError) {
      // The function raises readable messages: unknown booth code, pass not
      // registered for this fair, not registered to this booth.
      setError(describeError(rpcError));
      return;
    }

    setSuccess('Connected. Their passport is now visible to you.');
    setPassCode('');
    setNote('');
    onScanned();
  }

  return (
    <Dialog
      as="form"
      title="Scan a Fair Passport"
      eyebrow={`Booth ${exhibitor.booth_code} · ${exhibitor.fairs?.name ?? ''}`}
      onClose={onClose}
      onSubmit={handleSubmit}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Done
          </Button>
          <Button type="submit" loading={busy} icon={ScanLine}>
            Record visit
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}
      {success && (
        <div className="mb-5">
          <Alert tone="success">{success}</Alert>
        </div>
      )}

      <p className="text-muted leading-relaxed">
        Type the 8-character code from the student’s pass. Recording a visit
        gives you access to their passport — they chose to walk up to your
        booth, and they can revoke it afterwards.
      </p>

      <div className="mt-5 flex flex-col gap-4">
        <Field
          label="Pass code"
          hint="8 characters. There are no letter O or I, and no zero or one — if a character looks like one of those, it is the other."
        >
          <Input
            value={passCode}
            onChange={(e) => setPassCode(e.target.value.toUpperCase())}
            placeholder="SQ53 W4WS"
            autoFocus
            required
            className="font-mono tracking-[3px] text-[16px]"
          />
        </Field>

        <Field label="Which program were they asking about?">
          <Select value={programId} onChange={(e) => setProgramId(e.target.value)}>
            <option value="">Not specific</option>
            {(programs ?? []).map((program) => (
              <option key={program.id} value={program.id}>
                {program.name}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="How interested are they?">
          <Select value={interest} onChange={(e) => setInterest(e.target.value)}>
            <option value="high">High</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
          </Select>
        </Field>

        <div className="flex flex-col gap-2.5">
          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={followUp}
              onChange={(e) => setFollowUp(e.target.checked)}
              className="size-4 accent-accent"
            />
            <span className="text-[13.5px]">They want a follow-up</span>
          </label>
          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={scholarship}
              onChange={(e) => setScholarship(e.target.checked)}
              className="size-4 accent-accent"
            />
            <span className="text-[13.5px]">We discussed scholarships</span>
          </label>
        </div>

        <Field label="Note" hint="Optional. Goes in your lead list.">
          <Textarea
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Strong WASSCE results, needs funding information."
          />
        </Field>
      </div>
    </Dialog>
  );
}
