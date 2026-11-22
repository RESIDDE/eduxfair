import { useParams, useSearchParams } from 'react-router-dom';
import { Ban, BookmarkCheck, Users, VolumeX } from 'lucide-react';
import {
  Alert, Avatar, Badge, Loading, SegmentedControl, StatusBadge, SurfaceCard,
} from '../../../components/ui';
import { useFieldLabels, useQuery } from '../../../lib/hooks';
import { formatDate, formatDateTime, formatMoney } from '../../../lib/format';
import { countryName, STUDY_LEVELS } from '../../../lib/vocab';
import { lookupPeople, withLookups } from '../../../lib/admin';
import {
  DataState, Details, InstitutionChip, Pills, PersonChip, Prose, Section, roleLabel,
} from './parts';
import {
  ApplicationsList, CommentsList, ConversationsPanel, DocumentsList,
  MeetingsList, PostsList, ReportsList,
} from './lists';

/**
 * Everything about one account, on one page.
 *
 * The tabs follow what the account is: a student has a passport, documents and
 * applications; staff have an institution and the conversations it holds.
 * Every list is the same component the platform-wide pages use, narrowed to
 * this person.
 */
export default function AdminPersonPage() {
  const { id } = useParams();
  // The tab lives in the URL, so a link can point at "this student's documents".
  const [params, setParams] = useSearchParams();
  const tab = params.get('tab') ?? 'overview';
  const setTab = (next) => setParams(next === 'overview' ? {} : { tab: next }, { replace: true });

  const { data, loading, error } = useQuery(async (client) => {
    const [person, social, profile] = await Promise.all([
      client.from('admin_people').select('*').eq('id', id).maybeSingle(),
      client.from('social_profiles').select('*').eq('profile_id', id).maybeSingle(),
      client.from('profiles').select('*').eq('id', id).maybeSingle(),
    ]);
    const failed = person.error || social.error || profile.error;
    if (failed) return { data: null, error: failed };
    return { data: { person: person.data, social: social.data, profile: profile.data }, error: null };
  }, [id]);

  if (loading && !data) return <Loading label="Loading account" />;
  if (error) return <Alert tone="error">{error}</Alert>;
  if (!data?.person) return <Alert tone="error">No account with that id.</Alert>;

  const { person, social, profile } = data;
  const isStudent = person.role === 'student';
  const isStaff = person.role === 'institution_member' || Boolean(person.institution_id);

  const tabs = [
    { value: 'overview', label: 'Overview' },
    isStudent && { value: 'passport', label: 'Passport' },
    isStudent && { value: 'documents', label: 'Documents' },
    isStudent && { value: 'applications', label: 'Applications' },
    { value: 'messages', label: 'Messages' },
    { value: 'meetings', label: 'Meetings' },
    { value: 'posts', label: 'Posts' },
    { value: 'comments', label: 'Comments' },
    { value: 'connections', label: 'Connections' },
    { value: 'safety', label: 'Safety' },
  ].filter(Boolean);

  // Staff talk on behalf of their institution, so their conversations are the
  // institution's; a student's are their own.
  const conversationScope = isStudent || !person.institution_id
    ? { scope: (q) => q.eq('student_id', id), key: `student:${id}` }
    : { scope: (q) => q.eq('institution_id', person.institution_id), key: `inst:${person.institution_id}` };

  return (
    <div className="flex flex-col gap-5 pb-6">
      <SurfaceCard className="p-5">
        <div className="flex flex-wrap items-center gap-4">
          <Avatar name={person.full_name} src={person.avatar_url} size={64} />
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-[20px] font-bold">{person.full_name || 'Unnamed'}</h2>
              <Badge tone={person.role === 'admin' ? 'live' : 'neutral'} compact>{roleLabel(person.role)}</Badge>
              {person.is_restricted && (
                <Badge tone="error" compact>
                  {person.restriction_kind === 'suspended' ? 'Suspended' : 'Read only'}
                </Badge>
              )}
              {person.is_minor && <Badge tone="warning" compact>Minor</Badge>}
              {!person.email_confirmed && <Badge tone="warning" compact>Email unconfirmed</Badge>}
            </div>
            <div className="mt-1 text-[13px] text-muted">
              {person.email}
              {person.handle && <> · @{person.handle}</>}
              {person.country && <> · {countryName(person.country)}</>}
            </div>
            {person.institution_id && (
              <div className="mt-1.5 flex items-center gap-2 text-[12.5px] text-subtle">
                {person.member_role === 'owner' ? 'Owner of' : 'Staff at'}
                <InstitutionChip id={person.institution_id} institution={{ name: person.institution_name }} size={20} />
              </div>
            )}
          </div>
        </div>
      </SurfaceCard>

      <SegmentedControl value={tab} onChange={setTab} options={tabs} />

      {tab === 'overview' && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Section title="Account">
            <Details items={[
              ['Email', person.email],
              ['Phone', person.phone ?? profile?.phone],
              ['Country', person.country && countryName(person.country)],
              ['Date of birth', formatDate(profile?.date_of_birth)],
              ['Joined', formatDateTime(person.created_at)],
              ['Last signed in', person.last_sign_in_at ? formatDateTime(person.last_sign_in_at) : 'Never'],
              ['Role', roleLabel(person.role)],
              ['Account id', <code key="id" className="text-[11.5px] text-subtle">{person.id}</code>],
              person.is_restricted && ['Restriction', `${person.restriction_kind?.replace('_', ' ')}${
                person.restriction_until ? ` until ${formatDate(person.restriction_until)}` : ''}${
                person.restriction_reason ? ` — ${person.restriction_reason}` : ''}`],
            ]}
            />
          </Section>
          <Section title="Public profile">
            {social ? (
              <div className="flex flex-col gap-4">
                <Details items={[
                  ['Handle', social.handle && `@${social.handle}`],
                  ['Display name', social.display_name],
                  ['Followers', social.follower_count],
                  ['Following', social.following_count],
                  ['Posts', social.post_count],
                  ['Visible', social.is_public ? 'Public' : 'Private'],
                ]}
                />
                <div>
                  <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">Bio</div>
                  <Prose>{social.bio}</Prose>
                </div>
              </div>
            ) : (
              <span className="text-[13px] text-subtle">No public profile (no handle).</span>
            )}
          </Section>
          {isStaff && person.institution_id && (
            <Section title="Institution" className="xl:col-span-2">
              <InstitutionChip id={person.institution_id} institution={{ name: person.institution_name }} />
              <p className="mt-2 text-[12.5px] text-subtle">
                Their institution’s prospectus, programmes, team, applications and inbox are on its page.
              </p>
            </Section>
          )}
        </div>
      )}

      {tab === 'passport' && <PassportTab id={id} />}
      {tab === 'documents' && (
        <DocumentsList scope={(q) => q.eq('profile_id', id)} scopeKey={`person:${id}`} showOwner={false} />
      )}
      {tab === 'applications' && (
        <ApplicationsList scope={(q) => q.eq('profile_id', id)} scopeKey={`person:${id}`} hide={['student']} />
      )}
      {tab === 'messages' && (
        <ConversationsPanel scope={conversationScope.scope} scopeKey={conversationScope.key} />
      )}
      {tab === 'meetings' && (
        // A student's meetings are the ones they booked; staff's are the ones
        // they host.
        <MeetingsList
          scope={(q) => q.eq(isStudent ? 'student_id' : 'host_profile_id', id)}
          scopeKey={`person:${id}:${isStudent}`}
          hide={isStudent ? ['student'] : []}
        />
      )}
      {tab === 'posts' && <PostsList scope={(q) => q.eq('author_id', id)} scopeKey={`person:${id}`} />}
      {tab === 'comments' && <CommentsList scope={(q) => q.eq('author_id', id)} scopeKey={`person:${id}`} />}
      {tab === 'connections' && <ConnectionsTab id={id} />}
      {tab === 'safety' && <SafetyTab id={id} />}
    </div>
  );
}

function PassportTab({ id }) {
  const fieldLabels = useFieldLabels();
  const { data, loading, error } = useQuery(async (client) => {
    const [passport, shares, interests] = await Promise.all([
      client.from('student_passports').select('*').eq('profile_id', id).maybeSingle(),
      withLookups(
        client.from('passport_shares').select('*').eq('profile_id', id)
          .order('granted_at', { ascending: false }),
        { institutions: ['institution_id'] },
      ),
      withLookups(
        client.from('student_interests').select('*').eq('profile_id', id)
          .order('created_at', { ascending: false }),
        { programs: ['program_id'] },
      ),
    ]);
    const failed = passport.error || shares.error || interests.error;
    if (failed) return { data: null, error: failed };
    return { data: { passport: passport.data, shares: shares.data, interests: interests.data }, error: null };
  }, [id]);

  return (
    <DataState loading={loading && !data} error={error}>
      {data && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Section
            title="Education Passport"
            action={data.passport && <StatusBadge status={data.passport.verification_status} compact />}
            className="xl:col-span-2"
          >
            {data.passport ? (
              <div className="flex flex-col gap-4">
                <Details items={[
                  ['Completeness', `${data.passport.completeness ?? 0}%`],
                  ['Nationality', countryName(data.passport.nationality)],
                  ['Lives in', countryName(data.passport.current_country)],
                  ['Date of birth', formatDate(data.passport.date_of_birth)],
                  ['Highest qualification', data.passport.highest_qualification],
                  ['Grade', data.passport.grade_value != null
                    ? `${data.passport.grade_value} (${data.passport.grade_scheme ?? '—'})` : null],
                  ['English test', data.passport.english_test_name && data.passport.english_test_name !== 'none'
                    ? `${data.passport.english_test_name.toUpperCase()} ${data.passport.english_score ?? ''}` : null],
                  ['Budget', data.passport.budget_max
                    ? `${formatMoney(data.passport.budget_min ?? 0, data.passport.budget_currency ?? 'USD')} – ${
                      formatMoney(data.passport.budget_max, data.passport.budget_currency ?? 'USD')}` : null],
                  ['Intended intake', data.passport.intended_intake],
                  ['Target countries', <Pills key="c" values={(data.passport.target_countries ?? []).map(countryName)} />],
                  ['Target levels', <Pills key="l" values={(data.passport.target_levels ?? []).map((l) => STUDY_LEVELS[l] ?? l)} />],
                  ['Target fields', <Pills key="f" values={(data.passport.target_fields ?? []).map((f) => fieldLabels[f] ?? f)} />],
                  ['Verified', data.passport.verified_at ? formatDateTime(data.passport.verified_at) : null],
                  ['Last updated', formatDateTime(data.passport.updated_at)],
                ]}
                />
                <div>
                  <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">About them</div>
                  <Prose>{data.passport.bio}</Prose>
                </div>
              </div>
            ) : (
              <span className="text-[13px] text-subtle">They have not started a passport.</span>
            )}
          </Section>

          <Section title="Who they shared it with" count={data.shares.rows.length}>
            {data.shares.rows.length === 0 && <span className="text-[13px] text-subtle">Nobody yet.</span>}
            <div className="flex flex-col gap-2.5">
              {data.shares.rows.map((s) => (
                <div key={s.id} className="flex items-center justify-between gap-3">
                  <InstitutionChip id={s.institution_id} institution={data.shares.institutions[s.institution_id]} />
                  <span className="text-[12px] text-subtle text-right">
                    {s.reason && <>{s.reason} · </>}
                    {formatDate(s.granted_at)}
                    {s.revoked_at && <span className="text-error"> · revoked {formatDate(s.revoked_at)}</span>}
                  </span>
                </div>
              ))}
            </div>
          </Section>

          <Section title="Programmes they saved or asked about" count={data.interests.rows.length}>
            {data.interests.rows.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-col gap-2">
              {data.interests.rows.map((i) => (
                <div key={i.id} className="flex items-center justify-between gap-3 text-[13px]">
                  <span>{data.interests.programs[i.program_id]?.name ?? 'A programme'}</span>
                  <span className="text-[12px] text-subtle">
                    {i.kind === 'requested_info' ? 'Asked for info' : 'Saved'} · {formatDate(i.created_at)}
                  </span>
                </div>
              ))}
            </div>
          </Section>
        </div>
      )}
    </DataState>
  );
}

function ConnectionsTab({ id }) {
  const { data, loading, error } = useQuery(async (client) => {
    const [following, followers, institutions, blocksOut, blocksIn, mutes, bookmarks] = await Promise.all([
      client.from('follows').select('*').eq('follower_id', id),
      client.from('follows').select('*').eq('followee_id', id),
      withLookups(
        client.from('institution_follows').select('*').eq('student_id', id),
        { institutions: ['institution_id'] },
      ),
      client.from('blocks').select('*').eq('blocker_id', id),
      client.from('blocks').select('*').eq('blocked_id', id),
      client.from('mutes').select('*').eq('muter_id', id),
      client.from('post_bookmarks').select('*').eq('profile_id', id),
    ]);
    const failed = [following, followers, institutions, blocksOut, blocksIn, mutes, bookmarks].find((r) => r.error)?.error;
    if (failed) return { data: null, error: failed };
    const blocks = { data: [...blocksOut.data, ...blocksIn.data] };

    const ids = [
      ...following.data.map((f) => f.followee_id),
      ...followers.data.map((f) => f.follower_id),
      ...blocks.data.flatMap((b) => [b.blocker_id, b.blocked_id]),
      ...mutes.data.map((m) => m.muted_id),
    ];
    let people;
    try {
      people = await lookupPeople(ids);
    } catch (lookupError) {
      return { data: null, error: lookupError };
    }
    return {
      data: {
        following: following.data, followers: followers.data, institutions,
        blocks: blocks.data, mutes: mutes.data, bookmarks: bookmarks.data,
        people,
      },
      error: null,
    };
  }, [id]);

  return (
    <DataState loading={loading && !data} error={error}>
      {data && (
        <div className="grid gap-4 xl:grid-cols-2">
          <PeopleSection icon={Users} title="Follows" ids={data.following.map((f) => f.followee_id)} people={data.people} />
          <PeopleSection icon={Users} title="Followed by" ids={data.followers.map((f) => f.follower_id)} people={data.people} />
          <Section title="Institutions they follow" count={data.institutions.rows.length}>
            {data.institutions.rows.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-col gap-2">
              {data.institutions.rows.map((f) => (
                <InstitutionChip key={f.institution_id} id={f.institution_id} institution={data.institutions.institutions[f.institution_id]} />
              ))}
            </div>
          </Section>
          <Section title="Blocks" count={data.blocks.length}>
            {data.blocks.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-col gap-2">
              {data.blocks.map((b) => {
                const theyBlocked = b.blocker_id === id;
                const other = theyBlocked ? b.blocked_id : b.blocker_id;
                return (
                  <div key={`${b.blocker_id}-${b.blocked_id}`} className="flex items-center justify-between gap-3">
                    <PersonChip id={other} person={data.people[other]} />
                    <span className="flex items-center gap-1 text-[12px] text-subtle">
                      <Ban size={12} /> {theyBlocked ? 'blocked by this account' : 'has blocked this account'}
                    </span>
                  </div>
                );
              })}
            </div>
          </Section>
          <PeopleSection icon={VolumeX} title="Muted" ids={data.mutes.map((m) => m.muted_id)} people={data.people} />
          <Section title="Saved posts" count={data.bookmarks.length}>
            <span className="flex items-center gap-1.5 text-[13px] text-muted">
              <BookmarkCheck size={14} /> {data.bookmarks.length} post{data.bookmarks.length === 1 ? '' : 's'} saved
            </span>
          </Section>
        </div>
      )}
    </DataState>
  );
}

function PeopleSection({ title, ids, people }) {
  return (
    <Section title={title} count={ids.length}>
      {ids.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
      <div className="flex max-h-[360px] flex-col gap-2 overflow-y-auto scrollbar-thin">
        {ids.map((pid) => <PersonChip key={pid} id={pid} person={people[pid]} />)}
      </div>
    </Section>
  );
}

function SafetyTab({ id }) {
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      client.from('account_restrictions').select('*').eq('profile_id', id)
        .order('created_at', { ascending: false }),
      { people: ['created_by'] },
    ),
    [id],
  );

  return (
    <div className="flex flex-col gap-5">
      <Section title="Restrictions history">
        <DataState loading={loading && !data} error={error}>
          {data && data.rows.length === 0 && <span className="text-[13px] text-subtle">Never restricted.</span>}
          <div className="flex flex-col gap-2">
            {data?.rows.map((r) => (
              <div key={r.id} className="text-[13px]">
                <span className="font-semibold capitalize">{r.kind.replace('_', ' ')}</span>
                <span className="text-subtle">
                  {' '}· {formatDateTime(r.created_at)}
                  {r.created_by && ` by ${data.people[r.created_by]?.full_name ?? 'an admin'}`}
                  {r.until && ` · until ${formatDate(r.until)}`}
                  {r.lifted_at ? ` · lifted ${formatDate(r.lifted_at)}` : ' · active'}
                </span>
                {r.reason && <div className="text-muted">{r.reason}</div>}
              </div>
            ))}
          </div>
        </DataState>
      </Section>
      <div>
        <h3 className="mb-2 text-[14px] font-bold">Reports about this account</h3>
        <ReportsList scope={(q) => q.eq('subject_type', 'profile').eq('subject_id', id)} scopeKey={`about:${id}`} />
      </div>
      <div>
        <h3 className="mb-2 text-[14px] font-bold">Reports they made</h3>
        <ReportsList scope={(q) => q.eq('reporter_id', id)} scopeKey={`by:${id}`} />
      </div>
    </div>
  );
}
