import { Link } from 'react-router-dom';
import {
  Building2, Flag, GraduationCap, Radio, ShieldCheck, ShieldX, Users,
} from 'lucide-react';
import {
  Alert, Badge, EmptyState, Loading, SurfaceCard,
} from '../../components/ui';
import { useQuery } from '../../lib/hooks';
import { formatDateTime } from '../../lib/format';

/**
 * What needs an admin today, then the size of the platform.
 *
 * In that order on purpose. A dashboard that opens on totals tells you the
 * platform is alive; this one opens on the four queues that are nobody else's
 * job, because an unverified institution and an unread report are both things
 * only this console can clear.
 *
 * Counts use a head-only select so the database returns the number without
 * shipping the rows — the same approach AdminAnalyticsPage takes.
 */
export default function AdminOverviewPage() {
  const { data, loading, error } = useQuery(async (client) => {
    const head = (table, build = (q) => q) =>
      build(client.from(table).select('id', { count: 'exact', head: true }));

    const [
      pendingVerifications, openReports, unverifiedInstitutions, restricted,
      students, institutions, staff, programs, applications, liveSpaces,
      scheduledSpaces,
    ] = await Promise.all([
      head('verifications', (q) => q.eq('status', 'pending')),
      head('reports', (q) => q.eq('status', 'pending')),
      head('institutions', (q) => q.neq('verification_status', 'verified')),
      head('account_restrictions', (q) => q.is('lifted_at', null)),
      head('profiles', (q) => q.eq('role', 'student')),
      head('institutions'),
      head('profiles', (q) => q.eq('role', 'institution_member')),
      head('programs', (q) => q.eq('is_active', true)),
      head('applications'),
      head('spaces', (q) => q.eq('status', 'live')),
      head('spaces', (q) => q.eq('status', 'scheduled')),
    ]);

    const firstError = [
      pendingVerifications, openReports, unverifiedInstitutions, restricted,
      students, institutions, staff, programs, applications, liveSpaces,
      scheduledSpaces,
    ].find((r) => r.error);
    if (firstError) return { data: null, error: firstError.error };

    return {
      data: {
        pendingVerifications: pendingVerifications.count ?? 0,
        openReports: openReports.count ?? 0,
        unverifiedInstitutions: unverifiedInstitutions.count ?? 0,
        restricted: restricted.count ?? 0,
        students: students.count ?? 0,
        institutions: institutions.count ?? 0,
        staff: staff.count ?? 0,
        programs: programs.count ?? 0,
        applications: applications.count ?? 0,
        liveSpaces: liveSpaces.count ?? 0,
        scheduledSpaces: scheduledSpaces.count ?? 0,
      },
      error: null,
    };
  }, []);

  // The newest institutions, because a brand-new one is usually the thing an
  // admin is about to be asked about.
  const { data: recent } = useQuery(
    (client) => client
      .from('institutions')
      .select('id, name, country, kind, verification_status, created_at')
      .order('created_at', { ascending: false })
      .limit(6),
    [],
  );

  if (loading) return <Loading label="Reading the platform" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const queues = [
    {
      to: '/admin/verification',
      icon: ShieldCheck,
      label: 'Waiting for review',
      value: data.pendingVerifications,
      hint: 'Verification requests',
    },
    {
      to: '/admin/moderation',
      icon: Flag,
      label: 'Open reports',
      value: data.openReports,
      hint: 'Reported content and accounts',
    },
    {
      to: '/admin/institutions',
      icon: Building2,
      label: 'Not yet verified',
      value: data.unverifiedInstitutions,
      hint: 'Every Space they run gets a waiting room',
    },
    {
      to: '/admin/people',
      icon: ShieldX,
      label: 'Restricted accounts',
      value: data.restricted,
      hint: 'Suspended or read-only',
    },
  ];

  return (
    <div className="flex flex-col gap-6 pb-4">
      <section className="flex flex-col gap-3">
        <h2 className="text-[13px] font-bold uppercase tracking-[1px] text-subtle">
          Needs you
        </h2>
        <div className="grid gap-3 grid-cols-[repeat(auto-fit,minmax(200px,1fr))]">
          {queues.map((q) => (
            <Link key={q.to} to={q.to}>
              <SurfaceCard className="h-full p-4 transition-colors hover:bg-surface-variant">
                <div className="flex items-start justify-between gap-3">
                  <q.icon
                    size={18}
                    className={q.value > 0 ? 'text-accent' : 'text-subtle'}
                    strokeWidth={2.1}
                  />
                  {q.value > 0 && <Badge tone="warning" compact pulse>Open</Badge>}
                </div>
                <div className="mt-3 text-[30px] font-extrabold leading-none tracking-[-1px]">
                  {q.value}
                </div>
                <div className="mt-1.5 text-[13px] font-semibold">{q.label}</div>
                <div className="mt-0.5 text-[12px] leading-snug text-subtle">{q.hint}</div>
              </SurfaceCard>
            </Link>
          ))}
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-[13px] font-bold uppercase tracking-[1px] text-subtle">
          The platform
        </h2>
        <div className="grid gap-3 grid-cols-[repeat(auto-fit,minmax(150px,1fr))]">
          <Stat icon={Users} label="Students" value={data.students} />
          <Stat icon={Building2} label="Institutions" value={data.institutions} />
          <Stat icon={Users} label="Institution staff" value={data.staff} />
          <Stat icon={GraduationCap} label="Active programs" value={data.programs} />
          <Stat icon={GraduationCap} label="Applications" value={data.applications} />
          <Stat
            icon={Radio}
            label="Spaces"
            value={data.liveSpaces + data.scheduledSpaces}
            note={data.liveSpaces > 0 ? `${data.liveSpaces} live now` : 'none live'}
          />
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-[13px] font-bold uppercase tracking-[1px] text-subtle">
          Newest institutions
        </h2>
        {(recent ?? []).length === 0 ? (
          <EmptyState
            icon={Building2}
            title="No institutions yet"
            subtitle="They appear here as they sign themselves up."
          />
        ) : (
          <div className="flex flex-col gap-2">
            {(recent ?? []).map((inst) => (
              <Link key={inst.id} to="/admin/institutions">
                <SurfaceCard className="flex flex-wrap items-center gap-3 p-3.5 transition-colors hover:bg-surface-variant">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[14px] font-semibold">{inst.name}</div>
                    <div className="text-[12px] capitalize text-subtle">
                      {inst.kind} · {inst.country} · joined {formatDateTime(inst.created_at)}
                    </div>
                  </div>
                  <Badge
                    tone={inst.verification_status === 'verified' ? 'success' : 'warning'}
                    compact
                  >
                    {inst.verification_status}
                  </Badge>
                </SurfaceCard>
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function Stat({ icon: Icon, label, value, note }) {
  return (
    <SurfaceCard className="p-4">
      <Icon size={16} className="text-subtle" strokeWidth={2.1} />
      <div className="mt-2.5 text-[26px] font-extrabold leading-none tracking-[-0.8px]">
        {value}
      </div>
      <div className="mt-1 text-[12.5px] text-muted">{label}</div>
      {note && <div className="mt-0.5 text-[11.5px] text-subtle">{note}</div>}
    </SurfaceCard>
  );
}
