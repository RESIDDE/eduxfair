import { useState } from 'react';
import { Link } from 'react-router-dom';
import { BadgeCheck, Building2, ShieldX } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Dialog,
  EmptyRow,
  Field,
  Loading,
  SearchField,
  Select,
  TableCard,
  Td,
  Th,
  Toolbar,
  Tr,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { decideVerification } from '../../lib/verification';
import { formatDate } from '../../lib/format';
import { countryName, INSTITUTION_TIERS } from '../../lib/vocab';

/**
 * Institutions and their subscription tiers.
 *
 * Tier is changed here, on `institution_subscriptions` — which admin alone may
 * write. A guard trigger blocks institutions from writing `institutions.tier`
 * directly, so this is the only way a plan changes, and the sync trigger
 * propagates it to the institution row.
 *
 * Verification is settled here too. The queue only shows requests that exist,
 * and most institutions never raise one — domain verification needs an email
 * the institution can receive, which is exactly what a new listing often has
 * not set up yet. Without this an admin could read every status and change
 * none of them.
 *
 * It writes a `verifications` row rather than touching
 * `institutions.verification_status`: apply_verification_decision() propagates
 * the decision onto the institution, so the badge and the queue can never
 * disagree. Going the other way would make them.
 */
export default function AdminInstitutionsPage() {
  const { profile } = useAuth();
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState(null);
  const [deciding, setDeciding] = useState(null);
  const [actionError, setActionError] = useState(null);

  /**
   * Always lands as an UPDATE, never an insert-with-the-answer.
   *
   * `verifications_apply_decision` is a `before update of status` trigger, so a
   * row inserted already saying 'verified' propagates nothing and the
   * institution keeps its old badge — the queue and the listing silently
   * disagree, which is the one thing that trigger exists to prevent. So a
   * subject with no open request gets one inserted as 'pending' first, and the
   * decision is a second statement. `verify-institution-domain` does the same,
   * for the same reason.
   *
   * `verifications_one_open` allows one pending row per subject, which is what
   * makes the maybeSingle() below safe.
   */
  async function decide(institution, status) {
    setActionError(null);
    const writeError = await decideVerification({
      subjectType: 'institution',
      subjectId: institution.id,
      status,
      reviewer: profile,
    });
    setDeciding(null);
    if (writeError) setActionError(describeError(writeError));
    await reload();
  }

  const { data: institutions, loading, error, reload } = useQuery(
    (client) => {
      let query = client
        .from('institutions')
        .select('*, institution_subscriptions(tier, seats, status)')
        .order('created_at', { ascending: false })
        .limit(200);
      if (search.trim()) query = query.ilike('name', `%${search.trim()}%`);
      return query;
    },
    [search],
  );

  if (loading) return <Loading label="Loading institutions" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = institutions ?? [];

  return (
    <div className="flex flex-col gap-4 h-full">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <Toolbar summary={`${rows.length} institution${rows.length === 1 ? '' : 's'}`}>
        <SearchField
          value={search}
          onChange={setSearch}
          placeholder="Search by name"
        />
      </Toolbar>

      <TableCard minWidth={900}>
        <thead>
          <tr>
            <Th>Institution</Th>
            <Th>Country</Th>
            <Th>Domain</Th>
            <Th>Verification</Th>
            <Th>Plan</Th>
            <Th>Seats</Th>
            <Th>Added</Th>
            <Th />
          </tr>
        </thead>
        <tbody>
          {rows.map((institution) => {
            const subscription = institution.institution_subscriptions?.[0] ?? null;
            return (
              <Tr key={institution.id}>
                <Td className="font-semibold">
                  <Link
                    to={`/admin/institutions/${institution.id}`}
                    className="hover:text-accent transition-colors"
                  >
                    {institution.name}
                  </Link>
                </Td>
                <Td>{countryName(institution.country)}</Td>
                <Td className="font-mono text-[12px]">
                  {institution.email_domain ?? '—'}
                </Td>
                <Td>
                  <Badge
                    tone={
                      institution.verification_status === 'verified'
                        ? 'success'
                        : institution.verification_status === 'rejected'
                          ? 'error'
                          : institution.verification_status === 'pending'
                            ? 'warning'
                            : 'neutral'
                    }
                    compact
                  >
                    {institution.verification_status}
                  </Badge>
                </Td>
                <Td>{INSTITUTION_TIERS[institution.tier] ?? institution.tier}</Td>
                <Td className="tabular-nums">{subscription?.seats ?? 1}</Td>
                <Td>{formatDate(institution.created_at)}</Td>
                <Td>
                  <div className="flex items-center gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => setEditing({ institution, subscription })}
                    >
                      Plan
                    </Button>
                    {institution.verification_status === 'verified' ? (
                      <Button
                        size="sm"
                        variant="dangerGhost"
                        icon={ShieldX}
                        onClick={() => setDeciding({ institution, status: 'rejected' })}
                      >
                        Revoke
                      </Button>
                    ) : (
                      <Button
                        size="sm"
                        variant="glass"
                        icon={BadgeCheck}
                        onClick={() => setDeciding({ institution, status: 'verified' })}
                      >
                        Verify
                      </Button>
                    )}
                  </div>
                </Td>
              </Tr>
            );
          })}
          {rows.length === 0 && (
            <EmptyRow colSpan={8} icon={Building2}>
              No institutions
            </EmptyRow>
          )}
        </tbody>
      </TableCard>

      {deciding && (
        <Dialog
          title={
            deciding.status === 'verified'
              ? 'Verify this institution?'
              : 'Revoke verification?'
          }
          eyebrow={deciding.institution.name}
          width="max-w-[480px]"
          onClose={() => setDeciding(null)}
          footer={
            <>
              <Button variant="ghost" onClick={() => setDeciding(null)}>
                Cancel
              </Button>
              <Button
                variant={deciding.status === 'verified' ? 'primary' : 'danger'}
                onClick={() => decide(deciding.institution, deciding.status)}
              >
                {deciding.status === 'verified' ? 'Verify' : 'Revoke'}
              </Button>
            </>
          }
        >
          <div className="flex flex-col gap-3 text-[13.5px] leading-relaxed text-muted">
            {deciding.status === 'verified' ? (
              <>
                <p>
                  The badge says one narrow thing: that this listing is genuine.
                  It is <strong className="text-white">not</strong> a claim about
                  accreditation or programme quality, and students are told so.
                </p>
                <p>
                  Normally an institution earns it by receiving a code at
                  <span className="font-mono text-[12.5px] text-accent-light">
                    {' '}@{deciding.institution.email_domain ?? 'their domain'}
                  </span>
                  . Verifying by hand records you as the reviewer instead.
                </p>
                <p className="text-subtle">
                  It also lifts the forced waiting room on their Live Spaces.
                </p>
              </>
            ) : (
              <p>
                Their badge disappears from every listing and every post, and
                any Space they schedule goes back to a forced waiting room.
              </p>
            )}
          </div>
        </Dialog>
      )}

      {editing && (
        <PlanDialog
          {...editing}
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

function PlanDialog({ institution, subscription, onClose, onSaved }) {
  const [tier, setTier] = useState(subscription?.tier ?? institution.tier ?? 'basic');
  const [seats, setSeats] = useState(subscription?.seats ?? 1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    // Upsert because a listing created before subscriptions existed may have
    // no row; the sync trigger then updates institutions.tier.
    const { error: writeError } = await supabase
      .from('institution_subscriptions')
      .upsert(
        {
          institution_id: institution.id,
          tier,
          seats: Number(seats),
        },
        { onConflict: 'institution_id' },
      );

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
      title="Subscription plan"
      eyebrow={institution.name}
      onClose={onClose}
      onSubmit={handleSubmit}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            Save
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      <p className="text-muted leading-relaxed">
        Billing itself is Phase 2 — this records what the institution is entitled
        to. Institutions cannot change their own tier.
      </p>

      <div className="mt-5 grid grid-cols-2 gap-4">
        <Field label="Tier">
          <Select value={tier} onChange={(e) => setTier(e.target.value)}>
            {Object.entries(INSTITUTION_TIERS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Seats" hint="Admissions officers who can sign in.">
          <input
            type="number"
            min="1"
            value={seats}
            onChange={(e) => setSeats(e.target.value)}
            className="w-full h-11 px-4 rounded-tile bg-surface-variant border border-line text-white"
          />
        </Field>
      </div>
    </Dialog>
  );
}
