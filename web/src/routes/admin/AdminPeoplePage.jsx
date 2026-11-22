import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Eye, ShieldCheck, ShieldX, UserCog, Users } from 'lucide-react';
import {
  Alert, Badge, Button, Dialog, EmptyState, Field, Loading, SearchField,
  SegmentedControl, Select, SurfaceCard, Textarea,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDateTime } from '../../lib/format';
import { countryName } from '../../lib/vocab';

/** Mirrors the `user_role` enum. */
const ROLES = {
  student: 'Student',
  institution_member: 'Institution staff',
  educator: 'Educator',
  admin: 'Admin',
};

/** Mirrors `restriction_kind`. */
const RESTRICTIONS = {
  read_only: 'Read only — can browse, cannot post or message',
  suspended: 'Suspended — cannot use the platform',
};

/**
 * Every account, and the two things only an admin can do to one: change what
 * they are, and stop them using the platform.
 *
 * Reads `admin_people`, which is the only place the sign-in address is
 * available — `profiles` does not carry it, and two people with the same name
 * are otherwise indistinguishable. The view gates on `is_admin()` and returns
 * nothing to anyone else.
 *
 * Both actions go through ordinary policies rather than an RPC:
 * `profiles_update_admin` for the role, `restrictions_all_admin` for a
 * restriction. `guard_profile_role_change()` already exempts an admin, which is
 * what makes the role dropdown work at all — it is the same trigger that stops
 * a student promoting themselves.
 */
export default function AdminPeoplePage() {
  const { profile } = useAuth();
  const [roleFilter, setRoleFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState(null);
  const [restricting, setRestricting] = useState(null);
  const [actionError, setActionError] = useState(null);

  const { data: rows, loading, error, reload } = useQuery(
    (client) => {
      let query = client
        .from('admin_people')
        .select('*')
        .order('created_at', { ascending: false });
      if (roleFilter !== 'all') query = query.eq('role', roleFilter);
      return query.limit(500);
    },
    [roleFilter],
  );

  async function lift(person) {
    setActionError(null);
    const { error: writeError } = await supabase
      .from('account_restrictions')
      .update({ lifted_at: new Date().toISOString() })
      .eq('profile_id', person.id)
      .is('lifted_at', null);
    if (writeError) setActionError(describeError(writeError));
    await reload();
  }

  if (loading) return <Loading label="Loading accounts" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const term = search.trim().toLowerCase();
  const people = (rows ?? []).filter((p) => {
    if (!term) return true;
    return [p.full_name, p.email, p.handle, p.institution_name]
      .some((v) => (v ?? '').toLowerCase().includes(term));
  });

  return (
    <div className="flex flex-col gap-5 pb-4">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <SegmentedControl
          value={roleFilter}
          onChange={setRoleFilter}
          options={[
            { value: 'all', label: 'Everyone' },
            { value: 'student', label: 'Students' },
            { value: 'institution_member', label: 'Staff' },
            { value: 'educator', label: 'Educators' },
            { value: 'admin', label: 'Admins' },
          ]}
        />
        <SearchField
          value={search}
          onChange={setSearch}
          placeholder="Name, email, handle or institution"
        />
      </div>

      <span className="text-[13px] text-subtle">
        {people.length} account{people.length === 1 ? '' : 's'}
      </span>

      {people.length === 0 ? (
        <EmptyState
          icon={Users}
          title="Nobody here"
          subtitle={term ? 'Try a different search.' : 'No accounts with that role yet.'}
        />
      ) : (
        <div className="flex flex-col gap-2.5">
          {people.map((person) => (
            <SurfaceCard key={person.id} className="p-4">
              <div className="flex flex-wrap items-start gap-3.5">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <Link
                      to={`/admin/people/${person.id}`}
                      className="font-semibold hover:text-accent transition-colors"
                    >
                      {person.full_name || 'Unnamed'}
                    </Link>
                    <Badge
                      tone={person.role === 'admin' ? 'live' : 'neutral'}
                      compact
                    >
                      {ROLES[person.role] ?? person.role}
                    </Badge>
                    {person.is_restricted && (
                      <Badge tone="error" compact>
                        {person.restriction_kind === 'suspended' ? 'Suspended' : 'Read only'}
                      </Badge>
                    )}
                    {person.is_minor && <Badge tone="warning" compact>Minor</Badge>}
                    {person.id === profile?.id && (
                      <span className="text-[11px] text-subtle">(you)</span>
                    )}
                  </div>

                  <div className="mt-1 text-[12.5px] text-muted">
                    {person.email}
                    {person.handle && <> · @{person.handle}</>}
                    {person.country && <> · {countryName(person.country)}</>}
                  </div>

                  {person.institution_name && (
                    <div className="mt-0.5 text-[12.5px] text-subtle">
                      {person.member_role === 'owner' ? 'Owner of' : 'Officer at'}{' '}
                      {person.institution_name}
                      {person.institution_verification_status !== 'verified' && (
                        <> · <span className="text-warning">
                          {person.institution_verification_status}
                        </span></>
                      )}
                    </div>
                  )}

                  <div className="mt-1 text-[11.5px] text-subtle">
                    Joined {formatDateTime(person.created_at)}
                    {person.last_sign_in_at
                      ? ` · last seen ${formatDateTime(person.last_sign_in_at)}`
                      : ' · never signed in'}
                    {!person.email_confirmed && ' · email unconfirmed'}
                    {person.restriction_reason && ` · ${person.restriction_reason}`}
                  </div>
                </div>

                <div className="flex shrink-0 flex-wrap items-center gap-2">
                  <Link to={`/admin/people/${person.id}`}>
                    <Button size="sm" variant="glass" icon={Eye}>View everything</Button>
                  </Link>
                  <Button
                    size="sm"
                    variant="outline"
                    icon={UserCog}
                    onClick={() => setEditing(person)}
                  >
                    Role
                  </Button>
                  {person.is_restricted ? (
                    <Button
                      size="sm"
                      variant="glass"
                      icon={ShieldCheck}
                      onClick={() => lift(person)}
                    >
                      Lift
                    </Button>
                  ) : (
                    <Button
                      size="sm"
                      variant="dangerGhost"
                      icon={ShieldX}
                      onClick={() => setRestricting(person)}
                    >
                      Restrict
                    </Button>
                  )}
                </div>
              </div>
            </SurfaceCard>
          ))}
        </div>
      )}

      {editing && (
        <RoleDialog
          person={editing}
          isSelf={editing.id === profile?.id}
          onClose={() => setEditing(null)}
          onSaved={async () => { setEditing(null); await reload(); }}
        />
      )}

      {restricting && (
        <RestrictDialog
          person={restricting}
          createdBy={profile?.id}
          onClose={() => setRestricting(null)}
          onSaved={async () => { setRestricting(null); await reload(); }}
        />
      )}
    </div>
  );
}

function RoleDialog({ person, isSelf, onClose, onSaved }) {
  const [role, setRole] = useState(person.role);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const { error: writeError } = await supabase
      .from('profiles').update({ role }).eq('id', person.id);
    setBusy(false);
    if (writeError) setError(describeError(writeError));
    else await onSaved();
  }

  return (
    <Dialog
      as="form"
      title="Change what this account is"
      eyebrow={person.email}
      onClose={onClose}
      onSubmit={submit}
      width="max-w-[480px]"
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={busy} disabled={role === person.role}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <Field label="Role">
          <Select value={role} onChange={(e) => setRole(e.target.value)}>
            {Object.entries(ROLES).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </Field>

        {/* Not a warning about permissions — a warning about the door closing
            behind you. Only an admin can grant admin, so the last one to
            demote themselves cannot undo it from this console. */}
        {isSelf && role !== 'admin' && (
          <Alert tone="error">
            This is your own account. Taking admin off it signs you out of this
            console, and only another admin can put it back.
          </Alert>
        )}

        {role === 'admin' && person.role !== 'admin' && (
          <p className="text-[12.5px] leading-relaxed text-muted">
            An admin can read every student passport, resolve any verification,
            restrict any account and moderate anything on the platform.
          </p>
        )}

        {role === 'institution_member' && !person.institution_id && (
          <p className="text-[12.5px] leading-relaxed text-subtle">
            They have no institution yet, so they will be asked to create one on
            their next sign-in.
          </p>
        )}

        {role === 'educator' && (
          <p className="text-[12.5px] leading-relaxed text-warning">
            Educator has no console of its own yet. They will be routed to the
            institution shell and asked to create an institution, which is
            probably not what you want.
          </p>
        )}

        {error && <Alert tone="error">{error}</Alert>}
      </div>
    </Dialog>
  );
}

function RestrictDialog({ person, createdBy, onClose, onSaved }) {
  const [kind, setKind] = useState('read_only');
  const [reason, setReason] = useState('');
  const [days, setDays] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const until = days
      ? new Date(Date.now() + Number(days) * 86400000).toISOString()
      : null;

    const { error: writeError } = await supabase
      .from('account_restrictions')
      .insert({
        profile_id: person.id,
        kind,
        reason: reason.trim() || null,
        until,
        created_by: createdBy,
      });

    setBusy(false);
    if (writeError) setError(describeError(writeError));
    else await onSaved();
  }

  return (
    <Dialog
      as="form"
      title="Restrict this account"
      eyebrow={person.full_name || person.email}
      onClose={onClose}
      onSubmit={submit}
      width="max-w-[480px]"
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button variant="danger" type="submit" loading={busy}>Restrict</Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <Field label="What kind">
          <Select value={kind} onChange={(e) => setKind(e.target.value)}>
            {Object.entries(RESTRICTIONS).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </Field>

        <Field
          label="Why"
          hint="The person can read this. Write it for them, not for the log."
        >
          <Textarea
            rows={3}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={500}
          />
        </Field>

        <Field
          label="For how many days"
          hint="Leave blank for no end date. A restriction with an end lifts itself."
        >
          <input
            type="number"
            min={1}
            max={3650}
            value={days}
            onChange={(e) => setDays(e.target.value)}
            placeholder="blank = indefinite"
            className="h-11 w-full rounded-tile border border-line bg-surface px-4 text-[14px] text-white placeholder:text-subtle focus:border-accent-light focus:outline-none"
          />
        </Field>

        <p className="text-[12.5px] leading-relaxed text-subtle">
          A restricted account cannot join a live Space — `is_restricted()` is
          checked inside `join_space()`, so this takes effect in the room as well
          as in the feed.
        </p>

        {error && <Alert tone="error">{error}</Alert>}
      </div>
    </Dialog>
  );
}
