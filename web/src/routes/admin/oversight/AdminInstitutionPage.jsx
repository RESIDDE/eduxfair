import { useParams, useSearchParams } from 'react-router-dom';
import { ExternalLink, FileText, Mail, Phone } from 'lucide-react';
import {
  Alert, Avatar, Badge, Loading, SegmentedControl, StatusBadge, SurfaceCard,
  TableCard, Td, Th, Tr,
} from '../../../components/ui';
import { useFieldLabels, useQuery } from '../../../lib/hooks';
import { formatCount, formatDate, formatDateTime, formatMoney, tuitionRange } from '../../../lib/format';
import { countryName, INSTITUTION_TIERS, STUDY_LEVELS } from '../../../lib/vocab';
import { publicFileUrl, withLookups } from '../../../lib/admin';
import {
  DataState, Details, PersonChip, Pills, Prose, Section,
} from './parts';
import {
  ApplicationsList, ConversationsPanel, MeetingsList, PostsList,
} from './lists';

/**
 * Everything about one institution, on one page: its listing, the prospectus
 * students read (contacts included), its programmes and team, and everything
 * it does on the platform — applications, conversations, meetings and posts.
 */
export default function AdminInstitutionPage() {
  const { id } = useParams();
  // The tab lives in the URL, so a link can point at "this student's documents".
  const [params, setParams] = useSearchParams();
  const tab = params.get('tab') ?? 'overview';
  const setTab = (next) => setParams(next === 'overview' ? {} : { tab: next }, { replace: true });

  const { data, loading, error } = useQuery(async (client) => {
    const count = (table, column = 'institution_id') =>
      client.from(table).select('*', { count: 'exact', head: true }).eq(column, id);
    const [institution, subscription, programmes, team, applications, conversations, followers, posts] =
      await Promise.all([
        client.from('institutions').select('*').eq('id', id).maybeSingle(),
        client.from('institution_subscriptions').select('*').eq('institution_id', id).maybeSingle(),
        count('programs'),
        count('institution_members'),
        count('applications'),
        count('conversations'),
        count('institution_follows'),
        count('posts'),
      ]);
    const failed = [institution, subscription, programmes, team, applications, conversations, followers, posts]
      .find((r) => r.error)?.error;
    if (failed) return { data: null, error: failed };
    return {
      data: {
        institution: institution.data,
        subscription: subscription.data,
        counts: {
          programmes: programmes.count, team: team.count, applications: applications.count,
          conversations: conversations.count, followers: followers.count, posts: posts.count,
        },
      },
      error: null,
    };
  }, [id]);

  if (loading && !data) return <Loading label="Loading institution" />;
  if (error) return <Alert tone="error">{error}</Alert>;
  if (!data?.institution) return <Alert tone="error">No institution with that id.</Alert>;

  const { institution: inst, subscription, counts } = data;

  const tabs = [
    { value: 'overview', label: 'Overview' },
    { value: 'prospectus', label: 'Prospectus & contacts' },
    { value: 'programmes', label: 'Programmes', count: counts.programmes },
    { value: 'team', label: 'Team', count: counts.team },
    { value: 'students', label: 'Students' },
    { value: 'applications', label: 'Applications', count: counts.applications },
    { value: 'messages', label: 'Messages', count: counts.conversations },
    { value: 'meetings', label: 'Meetings' },
    { value: 'posts', label: 'Posts', count: counts.posts },
    { value: 'verification', label: 'Verification' },
  ];

  return (
    <div className="flex flex-col gap-5 pb-6">
      <SurfaceCard className="p-5">
        <div className="flex flex-wrap items-center gap-4">
          <Avatar name={inst.name} src={inst.logo_url} size={64} className="rounded-[14px]" />
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-[20px] font-bold">{inst.name}</h2>
              <StatusBadge status={inst.verification_status} compact />
              <Badge compact>{INSTITUTION_TIERS[inst.tier] ?? inst.tier}</Badge>
              {inst.kind && <Badge compact>{inst.kind}</Badge>}
            </div>
            <div className="mt-1 text-[13px] text-muted">
              {[inst.city, countryName(inst.country)].filter(Boolean).join(', ')}
              {inst.website && (
                <> · <a href={inst.website} target="_blank" rel="noreferrer" className="text-accent hover:underline">{inst.website}</a></>
              )}
            </div>
            <div className="mt-1 text-[12px] text-subtle">
              {formatCount(inst.follower_count)} followers · joined {formatDate(inst.created_at)}
            </div>
          </div>
        </div>
      </SurfaceCard>

      <SegmentedControl value={tab} onChange={setTab} options={tabs} />

      {tab === 'overview' && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Section title="Listing">
            <Details items={[
              ['Name', inst.name],
              ['Kind', inst.kind],
              ['Country', countryName(inst.country)],
              ['City', inst.city],
              ['Website', inst.website],
              ['Email domain', inst.email_domain],
              ['Verified', inst.verified_at ? formatDateTime(inst.verified_at) : null],
              ['Slug', inst.slug],
              ['Institution id', <code key="id" className="text-[11.5px] text-subtle">{inst.id}</code>],
            ]}
            />
            <div className="mt-4">
              <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">Description</div>
              <Prose>{inst.description}</Prose>
            </div>
          </Section>
          <div className="flex flex-col gap-4">
            <Section title="Activity">
              <Details items={[
                ['Programmes', counts.programmes],
                ['Team members', counts.team],
                ['Applications', counts.applications],
                ['Conversations', counts.conversations],
                ['Followers', counts.followers],
                ['Posts', counts.posts],
              ]}
              />
            </Section>
            <Section title="Subscription">
              {subscription ? (
                <Details items={[
                  ['Plan', INSTITUTION_TIERS[subscription.tier] ?? subscription.tier],
                  ['Status', subscription.status],
                  ['Seats', subscription.seats],
                  ['Period', `${formatDate(subscription.period_start)} – ${formatDate(subscription.period_end)}`],
                ]}
                />
              ) : <span className="text-[13px] text-subtle">No subscription record.</span>}
            </Section>
          </div>
        </div>
      )}

      {tab === 'prospectus' && <ProspectusTab id={id} />}
      {tab === 'programmes' && <ProgrammesTab id={id} />}
      {tab === 'team' && <TeamTab id={id} />}
      {tab === 'students' && <StudentsTab id={id} />}
      {tab === 'applications' && (
        <ApplicationsList scope={(q) => q.eq('institution_id', id)} scopeKey={`inst:${id}`} hide={['institution']} />
      )}
      {tab === 'messages' && (
        <ConversationsPanel scope={(q) => q.eq('institution_id', id)} scopeKey={`inst:${id}`} />
      )}
      {tab === 'meetings' && (
        <MeetingsList scope={(q) => q.eq('institution_id', id)} scopeKey={`inst:${id}`} hide={['institution']} />
      )}
      {tab === 'posts' && <PostsList scope={(q) => q.eq('institution_id', id)} scopeKey={`inst:${id}`} />}
      {tab === 'verification' && <VerificationTab id={id} />}
    </div>
  );
}

function ProspectusTab({ id }) {
  const { data, loading, error } = useQuery(async (client) => {
    const byInst = (table) => client.from(table).select('*').eq('institution_id', id);
    const [profile, contacts, intakes, scholarships, requirements, faqs, media] = await Promise.all([
      byInst('institution_profiles').maybeSingle(),
      byInst('institution_contacts').order('ord'),
      byInst('institution_intakes').order('ord'),
      byInst('institution_scholarships').order('ord'),
      byInst('institution_entry_requirements').order('ord'),
      byInst('institution_faqs').order('ord'),
      byInst('institution_media').order('ord'),
    ]);
    const failed = [profile, contacts, intakes, scholarships, requirements, faqs, media].find((r) => r.error)?.error;
    if (failed) return { data: null, error: failed };
    return {
      data: {
        profile: profile.data, contacts: contacts.data, intakes: intakes.data,
        scholarships: scholarships.data, requirements: requirements.data,
        faqs: faqs.data, media: media.data,
      },
      error: null,
    };
  }, [id]);

  return (
    <DataState loading={loading && !data} error={error}>
      {data && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Section title="Contacts" count={data.contacts.length} className="xl:col-span-2">
            {data.contacts.length === 0 && <span className="text-[13px] text-subtle">No contacts listed.</span>}
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
              {data.contacts.map((c) => (
                <div key={c.id} className="rounded-tile bg-white/[0.03] p-3.5">
                  <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">{c.role}</div>
                  <div className="mt-1 font-semibold">{c.name || '—'}</div>
                  {c.email && (
                    <a href={`mailto:${c.email}`} className="mt-1 flex items-center gap-1.5 text-[12.5px] text-accent hover:underline">
                      <Mail size={13} /> {c.email}
                    </a>
                  )}
                  {c.phone && (
                    <a href={`tel:${c.phone}`} className="mt-0.5 flex items-center gap-1.5 text-[12.5px] text-muted hover:text-white">
                      <Phone size={13} /> {c.phone}
                    </a>
                  )}
                </div>
              ))}
            </div>
          </Section>

          <Section title="About" className="xl:col-span-2">
            {data.profile ? (
              <div className="flex flex-col gap-4">
                <Details items={[
                  ['Tagline', data.profile.tagline],
                  ['Founded', data.profile.founded_year],
                  ['Students', data.profile.student_count && formatCount(data.profile.student_count)],
                  ['International students', data.profile.international_student_count && formatCount(data.profile.international_student_count)],
                  ['Cost of living', data.profile.cost_of_living_max
                    ? `${formatMoney(data.profile.cost_of_living_min ?? 0, data.profile.cost_currency ?? 'USD')} – ${
                      formatMoney(data.profile.cost_of_living_max, data.profile.cost_currency ?? 'USD')}` : null],
                  ['Application fee', data.profile.application_fee != null
                    ? formatMoney(data.profile.application_fee, data.profile.fee_currency ?? 'USD') : null],
                  ['Deposit', data.profile.deposit != null
                    ? formatMoney(data.profile.deposit, data.profile.fee_currency ?? 'USD') : null],
                  ['Accreditation', <Pills key="a" values={data.profile.accreditation} />],
                  ['Profile completeness', `${data.profile.completeness ?? 0}%`],
                ]}
                />
                {[['About', data.profile.about], ['Campus life', data.profile.campus_life], ['Accommodation', data.profile.accommodation]]
                  .map(([label, text]) => (
                    <div key={label}>
                      <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">{label}</div>
                      <Prose>{text}</Prose>
                    </div>
                  ))}
                {Array.isArray(data.profile.rankings) && data.profile.rankings.length > 0 && (
                  <div>
                    <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">Rankings</div>
                    <ul className="mt-1 text-[13px]">
                      {data.profile.rankings.map((r, i) => (
                        <li key={i}>#{r.rank ?? '—'} · {r.body}{r.year ? ` (${r.year})` : ''}</li>
                      ))}
                    </ul>
                  </div>
                )}
                {data.profile.socials && Object.keys(data.profile.socials).length > 0 && (
                  <div>
                    <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">Social links</div>
                    <div className="mt-1 flex flex-wrap gap-3 text-[13px]">
                      {Object.entries(data.profile.socials).map(([k, v]) => (
                        <a key={k} href={v} target="_blank" rel="noreferrer" className="text-accent hover:underline capitalize">{k}</a>
                      ))}
                    </div>
                  </div>
                )}
                {Array.isArray(data.profile.application_steps) && data.profile.application_steps.length > 0 && (
                  <div>
                    <div className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">How to apply</div>
                    <ol className="mt-1 list-decimal pl-5 text-[13px]">
                      {data.profile.application_steps.map((s, i) => (
                        <li key={i}><span className="font-semibold">{s.title}</span>{s.detail && <span className="text-muted"> — {s.detail}</span>}</li>
                      ))}
                    </ol>
                  </div>
                )}
              </div>
            ) : <span className="text-[13px] text-subtle">No prospectus written yet.</span>}
          </Section>

          <Section title="Intakes" count={data.intakes.length}>
            {data.intakes.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            {data.intakes.map((i) => (
              <div key={i.id} className="py-1.5 text-[13px]">
                <span className="font-semibold">{i.label}</span>
                <span className="text-subtle">
                  {' '}· applications {formatDate(i.applications_open)} – {formatDate(i.applications_close)} · starts {formatDate(i.term_starts)}
                </span>
              </div>
            ))}
          </Section>

          <Section title="Scholarships" count={data.scholarships.length}>
            {data.scholarships.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            {data.scholarships.map((s) => (
              <div key={s.id} className="py-1.5 text-[13px]">
                <div className="font-semibold">
                  {s.name}
                  {s.amount != null && <span className="font-normal text-muted"> · {formatMoney(s.amount, s.currency ?? 'USD')}</span>}
                </div>
                <div className="text-subtle">
                  {[s.coverage, s.criteria, s.deadline && `deadline ${formatDate(s.deadline)}`].filter(Boolean).join(' · ')}
                </div>
              </div>
            ))}
          </Section>

          <Section title="Entry requirements" count={data.requirements.length} className="xl:col-span-2">
            {data.requirements.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            {data.requirements.length > 0 && (
              <TableCard minWidth={720} className="min-h-0 border-0">
                <thead>
                  <tr><Th>Applying from</Th><Th>Level</Th><Th>Qualification</Th><Th>Minimum grade</Th><Th>English</Th><Th>Notes</Th></tr>
                </thead>
                <tbody>
                  {data.requirements.map((r) => (
                    <Tr key={r.id}>
                      <Td>{r.from_country ? countryName(r.from_country) : 'Anywhere'}</Td>
                      <Td>{STUDY_LEVELS[r.level] ?? r.level ?? 'Any'}</Td>
                      <Td>{r.qualification ?? '—'}</Td>
                      <Td>{r.min_grade_value != null ? `${r.min_grade_value} (${r.min_grade_scheme})` : '—'}</Td>
                      <Td>{r.min_english_band ?? '—'}</Td>
                      <Td className="text-muted">{[...(r.additional ?? []), r.note].filter(Boolean).join(' · ') || '—'}</Td>
                    </Tr>
                  ))}
                </tbody>
              </TableCard>
            )}
          </Section>

          <Section title="Questions and answers" count={data.faqs.length}>
            {data.faqs.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            {data.faqs.map((f) => (
              <div key={f.id} className="py-2">
                <div className="text-[13px] font-semibold">{f.question}</div>
                <div className="text-[13px] text-muted whitespace-pre-wrap">{f.answer}</div>
              </div>
            ))}
          </Section>

          <Section title="Photos, brochures and videos" count={data.media.length}>
            {data.media.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-wrap gap-2">
              {data.media.map((m) => {
                const url = m.external_url ?? publicFileUrl('institution-media', m.storage_path);
                if (m.kind === 'photo') {
                  return (
                    <a key={m.id} href={url} target="_blank" rel="noreferrer" title={m.caption ?? ''}>
                      <img src={url} alt={m.caption ?? ''} className="h-24 w-32 rounded-tile object-cover bg-surface-variant" />
                    </a>
                  );
                }
                return (
                  <a key={m.id} href={url} target="_blank" rel="noreferrer"
                    className="flex items-center gap-1.5 rounded-tile bg-white/[0.04] px-3 py-2 text-[12.5px] hover:text-accent">
                    {m.kind === 'brochure' ? <FileText size={14} /> : <ExternalLink size={14} />}
                    {m.caption || (m.kind === 'brochure' ? 'Brochure' : 'Video')}
                  </a>
                );
              })}
            </div>
          </Section>
        </div>
      )}
    </DataState>
  );
}

function ProgrammesTab({ id }) {
  const labels = useFieldLabels();
  const { data, loading, error } = useQuery(
    (client) => client.from('programs').select('*').eq('institution_id', id).order('name'),
    [id],
  );
  const rows = data ?? [];
  return (
    <DataState loading={loading && !data} error={error} empty={rows.length === 0} emptyTitle="No programmes">
      <TableCard minWidth={900}>
        <thead>
          <tr><Th>Programme</Th><Th>Level</Th><Th>Field</Th><Th>Tuition</Th><Th>Intakes</Th><Th>Entry</Th><Th>Status</Th></tr>
        </thead>
        <tbody>
          {rows.map((p) => (
            <Tr key={p.id}>
              <Td className="font-semibold">
                {p.name}
                {p.scholarship_available && <div className="text-[11.5px] font-normal text-success">Scholarship available</div>}
              </Td>
              <Td>{STUDY_LEVELS[p.level] ?? p.level}</Td>
              <Td>{labels[p.field_of_study] ?? p.field_of_study}</Td>
              <Td className="whitespace-nowrap">{tuitionRange(p)}</Td>
              <Td>{(p.intakes ?? []).join(', ') || '—'}</Td>
              <Td className="text-muted">
                {p.min_grade_value != null ? `${p.min_grade_value} ${p.min_grade_scheme ?? ''}` : '—'}
                {p.min_english_band != null && ` · English ${p.min_english_band}`}
              </Td>
              <Td>{p.is_active ? <Badge tone="success" compact>Active</Badge> : <Badge compact>Hidden</Badge>}</Td>
            </Tr>
          ))}
        </tbody>
      </TableCard>
    </DataState>
  );
}

function TeamTab({ id }) {
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      client.from('institution_members').select('*').eq('institution_id', id).order('created_at'),
      { people: ['profile_id'] },
    ),
    [id],
  );
  const rows = data?.rows ?? [];
  return (
    <DataState loading={loading && !data} error={error} empty={rows.length === 0} emptyTitle="No team members">
      <TableCard minWidth={600}>
        <thead><tr><Th>Person</Th><Th>Role</Th><Th>Joined the team</Th></tr></thead>
        <tbody>
          {rows.map((m) => (
            <Tr key={m.id}>
              <Td><PersonChip id={m.profile_id} person={data.people[m.profile_id]} /></Td>
              <Td>{m.member_role === 'owner' ? 'Owner' : 'Admissions officer'}</Td>
              <Td className="text-muted">{formatDate(m.created_at)}</Td>
            </Tr>
          ))}
        </tbody>
      </TableCard>
    </DataState>
  );
}

function StudentsTab({ id }) {
  const { data, loading, error } = useQuery(async (client) => {
    const [shares, interests, followers] = await Promise.all([
      withLookups(
        client.from('passport_shares').select('*').eq('institution_id', id).order('granted_at', { ascending: false }),
        { people: ['profile_id'] },
      ),
      withLookups(
        client.from('institution_interests').select('*').eq('institution_id', id).order('created_at', { ascending: false }),
        { people: ['profile_id', 'created_by'], programs: ['program_id'] },
      ),
      withLookups(
        client.from('institution_follows').select('*').eq('institution_id', id).order('created_at', { ascending: false }),
        { people: ['student_id'] },
      ),
    ]);
    const failed = [shares, interests, followers].find((r) => r.error)?.error;
    if (failed) return { data: null, error: failed };
    return { data: { shares: shares.data, interests: interests.data, followers: followers.data }, error: null };
  }, [id]);

  return (
    <DataState loading={loading && !data} error={error}>
      {data && (
        <div className="grid gap-4 xl:grid-cols-3">
          <Section title="Passports shared with them" count={data.shares.rows.length}>
            {data.shares.rows.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-col gap-2.5">
              {data.shares.rows.map((s) => (
                <div key={s.id}>
                  <PersonChip id={s.profile_id} person={data.shares.people[s.profile_id]} />
                  <div className="pl-9 text-[11.5px] text-subtle">
                    {s.reason && `${s.reason} · `}{formatDate(s.granted_at)}
                    {s.revoked_at && <span className="text-error"> · revoked</span>}
                  </div>
                </div>
              ))}
            </div>
          </Section>
          <Section title="Students they shortlisted or invited" count={data.interests.rows.length}>
            {data.interests.rows.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-col gap-2.5">
              {data.interests.rows.map((i) => (
                <div key={i.id}>
                  <PersonChip id={i.profile_id} person={data.interests.people[i.profile_id]} />
                  <div className="pl-9 text-[11.5px] text-subtle">
                    <span className="capitalize">{i.kind}</span>
                    {data.interests.programs[i.program_id] && ` · ${data.interests.programs[i.program_id].name}`}
                    {' '}· {formatDate(i.created_at)}
                    {i.note && <div className="text-muted">{i.note}</div>}
                  </div>
                </div>
              ))}
            </div>
          </Section>
          <Section title="Followers" count={data.followers.rows.length}>
            {data.followers.rows.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex max-h-[480px] flex-col gap-2 overflow-y-auto scrollbar-thin">
              {data.followers.rows.map((f) => (
                <PersonChip key={f.student_id} id={f.student_id} person={data.followers.people[f.student_id]} />
              ))}
            </div>
          </Section>
        </div>
      )}
    </DataState>
  );
}

function VerificationTab({ id }) {
  const { data, loading, error } = useQuery(async (client) => {
    const [decisions, domains] = await Promise.all([
      withLookups(
        client.from('verifications').select('*')
          .eq('subject_type', 'institution').eq('subject_id', id)
          .order('created_at', { ascending: false }),
        { people: ['reviewer_id'] },
      ),
      // Named columns: the row also carries the token hash, which nobody needs to see.
      client.from('institution_domain_verifications')
        .select('id, email, domain, expires_at, consumed_at, attempts, created_at')
        .eq('institution_id', id)
        .order('created_at', { ascending: false }),
    ]);
    const failed = decisions.error || domains.error;
    if (failed) return { data: null, error: failed };
    return { data: { decisions: decisions.data, domains: domains.data }, error: null };
  }, [id]);

  return (
    <DataState loading={loading && !data} error={error}>
      {data && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Section title="Verification decisions" count={data.decisions.rows.length}>
            {data.decisions.rows.length === 0 && <span className="text-[13px] text-subtle">No requests or decisions yet.</span>}
            <div className="flex flex-col gap-3">
              {data.decisions.rows.map((v) => (
                <div key={v.id} className="text-[13px]">
                  <div className="flex items-center gap-2">
                    <StatusBadge status={v.status} compact />
                    <span className="text-subtle">{formatDateTime(v.decided_at ?? v.created_at)}</span>
                  </div>
                  <div className="mt-1 text-muted">
                    {v.evidence?.method && <>Method: {String(v.evidence.method).replace(/_/g, ' ')}</>}
                    {v.reviewer_id && <> · by {data.decisions.people[v.reviewer_id]?.full_name ?? 'an admin'}</>}
                  </div>
                  {v.review_note && <div className="text-subtle">{v.review_note}</div>}
                </div>
              ))}
            </div>
          </Section>
          <Section title="Domain email checks" count={data.domains.length}>
            {data.domains.length === 0 && <span className="text-[13px] text-subtle">None.</span>}
            <div className="flex flex-col gap-2">
              {data.domains.map((d) => (
                <div key={d.id} className="text-[13px]">
                  <span className="font-semibold">{d.email}</span>
                  <span className="text-subtle">
                    {' '}· {formatDateTime(d.created_at)} · {d.attempts} attempt{d.attempts === 1 ? '' : 's'}
                    {d.consumed_at ? ' · confirmed' : new Date(d.expires_at) < new Date() ? ' · expired' : ' · waiting'}
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
