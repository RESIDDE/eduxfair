import { Link } from 'react-router-dom';
import {
  CalendarCheck,
  FileText,
  Inbox,
  Sparkles,
  TrendingUp,
  Users,
} from 'lucide-react';
import {
  Alert,
  CardHeader,
  EmptyState,
  Loading,
  StatsStrip,
  SurfaceCard,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useFieldLabels, useQuery } from '../../lib/hooks';
import { formatCount } from '../../lib/format';
import { countryName, STUDY_LEVELS } from '../../lib/vocab';

/**
 * The pitch, made concrete: how many students currently match this
 * institution's programs, and where that demand is coming from.
 *
 * Everything here is pseudonymous or aggregate. Identities require a
 * passport share, which is the student's decision.
 */
export default function DashboardPage() {
  const { institutionId, institution } = useAuth();
  const fieldLabels = useFieldLabels();

  const { data: summary, loading, error } = useQuery(
    (client) =>
      client.rpc('my_institution_demand', { p_institution_id: institutionId }),
    [institutionId],
  );

  // Aggregate demand across the platform, not just this institution's matches.
  // The view suppresses any cell below five students so a small cell cannot
  // re-identify anyone.
  const { data: demand } = useQuery(
    (client) =>
      client
        .from('student_demand_stats')
        .select('*')
        .eq('target_country', institution?.country ?? '')
        .order('student_count', { ascending: false })
        .limit(40),
    [institution?.country],
  );

  if (loading) return <Loading label="Loading your dashboard" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const stats = summary ?? {};

  const byCountry = aggregate(demand ?? [], 'student_country');
  const byField = aggregate(demand ?? [], 'target_field');
  const byLevel = aggregate(demand ?? [], 'target_level');

  return (
    <div className="flex flex-col gap-6 pb-4">
      {institution?.verification_status !== 'verified' && (
        <Alert tone="error">
          Your listing is not verified yet. Verify your email domain in{' '}
          <Link to="/institution/settings" className="underline font-semibold">
            Settings
          </Link>{' '}
          — students are shown verified institutions first.
        </Alert>
      )}

      {/* The headline number: students who match, right now. */}
      <SurfaceCard className="p-7">
        <div className="flex items-start gap-5 flex-wrap">
          <div className="size-14 rounded-tile bg-accent/12 grid place-items-center shrink-0">
            <Sparkles size={26} className="text-accent" strokeWidth={2.1} />
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-[13px] text-subtle font-semibold uppercase tracking-[1.1px]">
              Students looking for what you offer
            </div>
            <div className="mt-1 text-[44px] font-extrabold leading-none gradient-hero-text">
              {formatCount(stats.matched_students)}
            </div>
            <p className="mt-3 text-muted leading-relaxed max-w-prose">
              These students match one of your active programs on destination,
              level, field and entry requirements. You can invite them before
              they ever apply — they stay anonymous until they choose to share
              their passport.
            </p>
            <Link
              to="/institution/students"
              className="mt-4 inline-flex items-center gap-2 text-accent font-semibold text-[13.5px] hover:brightness-110"
            >
              Browse matched students →
            </Link>
          </div>
        </div>
      </SurfaceCard>

      <StatsStrip
        items={[
          {
            label: 'Passports shared with you',
            value: formatCount(stats.shared_passports),
            tone: 'text-success',
          },
          {
            label: 'Open applications',
            value: formatCount(stats.open_applications),
          },
          {
            label: 'Meeting requests',
            value: formatCount(stats.pending_appointments),
            tone: Number(stats.pending_appointments) > 0 ? 'text-warning' : undefined,
          },
          {
            label: 'Unread threads',
            value: formatCount(stats.unread_conversations),
          },
        ]}
      />

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-5">
        <SurfaceCard className="p-6">
          <CardHeader
            icon={Users}
            title="Where demand comes from"
            subtitle={`Students seeking ${countryName(institution?.country)}`}
          />
          <DemandList rows={byCountry} labelFn={countryName} />
        </SurfaceCard>

        <SurfaceCard className="p-6">
          <CardHeader
            icon={TrendingUp}
            title="Most requested fields"
            subtitle="Across the platform"
          />
          <DemandList
            rows={byField}
            labelFn={(slug) => fieldLabels[slug] ?? slug}
          />
        </SurfaceCard>

        <SurfaceCard className="p-6">
          <CardHeader icon={FileText} title="By study level" />
          <DemandList
            rows={byLevel}
            labelFn={(level) => STUDY_LEVELS[level] ?? level}
          />
        </SurfaceCard>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        <QuickLink
          to="/institution/appointments"
          icon={CalendarCheck}
          title="Meeting requests"
          body={
            Number(stats.pending_appointments) > 0
              ? `${stats.pending_appointments} student${
                  Number(stats.pending_appointments) === 1 ? '' : 's'
                } waiting for you to confirm a time.`
              : 'No requests waiting. Publish availability so students can book.'
          }
        />
        <QuickLink
          to="/institution/inbox"
          icon={Inbox}
          title="Inbox"
          body={
            Number(stats.unread_conversations) > 0
              ? `${stats.unread_conversations} unread conversation${
                  Number(stats.unread_conversations) === 1 ? '' : 's'
                }.`
              : 'No unread messages.'
          }
        />
      </div>
    </div>
  );
}

/** Sums the exploded demand rows by one dimension. */
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
    .slice(0, 6);
}

function DemandList({ rows, labelFn }) {
  if (rows.length === 0) {
    return (
      <div className="mt-4">
        <EmptyState
          icon={TrendingUp}
          title="Not enough data yet"
          subtitle="Demand appears once at least five students share the same goal — small groups are suppressed so no individual can be identified."
        />
      </div>
    );
  }

  const max = Math.max(...rows.map((r) => r.count));

  return (
    <div className="mt-5 flex flex-col gap-3">
      {rows.map((row) => (
        <div key={row.name}>
          <div className="flex items-baseline justify-between gap-3">
            <span className="text-[13px] truncate">{labelFn(row.name)}</span>
            <span className="text-[13px] font-bold tabular-nums shrink-0">
              {formatCount(row.count)}
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

function QuickLink({ to, icon: Icon, title, body }) {
  return (
    <Link to={to}>
      <SurfaceCard className="p-5 h-full hover:bg-white/[0.03] transition-colors">
        <div className="flex items-start gap-4">
          <div className="size-10 rounded-tile bg-surface-variant grid place-items-center shrink-0">
            <Icon size={19} className="text-accent" strokeWidth={2.1} />
          </div>
          <div className="min-w-0">
            <div className="font-semibold">{title}</div>
            <p className="mt-1 text-[13px] text-muted leading-relaxed">{body}</p>
          </div>
        </div>
      </SurfaceCard>
    </Link>
  );
}
