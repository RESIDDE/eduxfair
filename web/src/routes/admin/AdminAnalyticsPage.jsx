import { ChartNoAxesColumn, GraduationCap, Send, Users } from 'lucide-react';
import {
  Alert,
  CardHeader,
  EmptyState,
  Loading,
  StatsStrip,
  SurfaceCard,
} from '../../components/ui';
import { useFieldLabels, useQuery } from '../../lib/hooks';
import { formatCount } from '../../lib/format';
import { countryName, STUDY_LEVELS } from '../../lib/vocab';

/**
 * Platform totals and where demand is concentrated.
 *
 * Counts use a head-only select so the database returns the count without
 * shipping the rows. Admin RLS covers every table, so these are true totals.
 */
export default function AdminAnalyticsPage() {
  const fieldLabels = useFieldLabels();

  const { data: counts, loading, error } = useQuery(async (client) => {
    const [students, institutions, programs, applications, shares, visits] =
      await Promise.all([
        client.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'student'),
        client.from('institutions').select('id', { count: 'exact', head: true }),
        client.from('programs').select('id', { count: 'exact', head: true }).eq('is_active', true),
        client.from('applications').select('id', { count: 'exact', head: true }),
        client
          .from('passport_shares')
          .select('id', { count: 'exact', head: true })
          .is('revoked_at', null),
        client.from('booth_visits').select('id', { count: 'exact', head: true }),
      ]);

    return {
      data: {
        students: students.count ?? 0,
        institutions: institutions.count ?? 0,
        programs: programs.count ?? 0,
        applications: applications.count ?? 0,
        shares: shares.count ?? 0,
        visits: visits.count ?? 0,
      },
      error:
        students.error ??
        institutions.error ??
        programs.error ??
        applications.error ??
        shares.error ??
        visits.error ??
        null,
    };
  }, []);

  const { data: demand } = useQuery(
    (client) =>
      client
        .from('student_demand_stats')
        .select('*')
        .order('student_count', { ascending: false })
        .limit(200),
    [],
  );

  if (loading) return <Loading label="Crunching the numbers" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = demand ?? [];
  const byDestination = aggregate(rows, 'target_country');
  const byOrigin = aggregate(rows, 'student_country');
  const byField = aggregate(rows, 'target_field');
  const byLevel = aggregate(rows, 'target_level');

  return (
    <div className="flex flex-col gap-5 pb-4">
      <StatsStrip
        items={[
          { label: 'Students', value: formatCount(counts.students) },
          { label: 'Institutions', value: formatCount(counts.institutions) },
          { label: 'Live programs', value: formatCount(counts.programs) },
          { label: 'Applications', value: formatCount(counts.applications) },
        ]}
      />
      <StatsStrip
        items={[
          {
            label: 'Active passport shares',
            value: formatCount(counts.shares),
            tone: 'text-success',
          },
          { label: 'Booth connections', value: formatCount(counts.visits) },
        ]}
      />

      <SurfaceCard className="p-4">
        <p className="text-[12.5px] text-muted leading-relaxed">
          Demand figures come from{' '}
          <code className="text-accent-light">student_demand_stats</code>, which
          suppresses any group smaller than five students. Totals below will
          therefore read lower than the student count above — that is the
          k-anonymity floor doing its job, not a bug.
        </p>
      </SurfaceCard>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-5">
        <SurfaceCard className="p-6">
          <CardHeader
            icon={GraduationCap}
            title="Most wanted destinations"
            subtitle="Where students want to study"
          />
          <Bars rows={byDestination} labelFn={countryName} />
        </SurfaceCard>

        <SurfaceCard className="p-6">
          <CardHeader
            icon={Users}
            title="Where students are applying from"
            subtitle="Your acquisition base"
          />
          <Bars rows={byOrigin} labelFn={countryName} />
        </SurfaceCard>

        <SurfaceCard className="p-6">
          <CardHeader
            icon={ChartNoAxesColumn}
            title="Most requested fields"
            subtitle="What institutions should be offering"
          />
          <Bars rows={byField} labelFn={(slug) => fieldLabels[slug] ?? slug} />
        </SurfaceCard>

        <SurfaceCard className="p-6">
          <CardHeader icon={Send} title="By study level" />
          <Bars rows={byLevel} labelFn={(level) => STUDY_LEVELS[level] ?? level} />
        </SurfaceCard>
      </div>
    </div>
  );
}

function aggregate(rows, key) {
  const totals = new Map();
  for (const row of rows) {
    const value = row[key];
    if (!value) continue;
    totals.set(value, (totals.get(value) ?? 0) + Number(row.student_count ?? 0));
  }
  return [...totals.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
}

function Bars({ rows, labelFn }) {
  if (rows.length === 0) {
    return (
      <div className="mt-4">
        <EmptyState
          icon={ChartNoAxesColumn}
          title="Not enough data yet"
          subtitle="Groups of fewer than five students are suppressed, so figures appear once there is enough volume."
        />
      </div>
    );
  }

  const max = Math.max(...rows.map((r) => r.count));
  const total = rows.reduce((sum, r) => sum + r.count, 0);

  return (
    <div className="mt-5 flex flex-col gap-3">
      {rows.map((row) => (
        <div key={row.name}>
          <div className="flex items-baseline justify-between gap-3">
            <span className="text-[13px] truncate">{labelFn(row.name)}</span>
            <span className="text-[13px] shrink-0 tabular-nums">
              <span className="font-bold">{formatCount(row.count)}</span>
              <span className="text-subtle ml-2">
                {Math.round((row.count / total) * 100)}%
              </span>
            </span>
          </div>
          <div className="mt-1.5 h-1.5 rounded-full bg-surface-variant overflow-hidden">
            <div
              className="h-full rounded-full gradient-accent"
              style={{ width: `${Math.max(4, (row.count / max) * 100)}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
