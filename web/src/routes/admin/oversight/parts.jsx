import { Link } from 'react-router-dom';
import { Alert, Avatar, Badge, EmptyState, Loading, SurfaceCard } from '../../../components/ui';

/**
 * Small pieces shared by the oversight pages — the person and institution
 * pages and the platform-wide lists.
 */

const ROLE_LABELS = {
  student: 'Student',
  institution_member: 'Institution staff',
  educator: 'Educator',
  admin: 'Admin',
};
export const roleLabel = (role) => ROLE_LABELS[role] ?? role ?? '—';

/** A person's name, linking to everything about them. */
export function PersonChip({ id, person, size = 26, sub = 'email' }) {
  if (!id) return <span className="text-subtle">—</span>;
  const name = person?.full_name || person?.email || 'Deleted account';
  const detail = sub === 'email' ? person?.email : sub === 'role' ? roleLabel(person?.role) : null;
  return (
    <Link
      to={`/admin/people/${id}`}
      onClick={(e) => e.stopPropagation()}
      className="inline-flex min-w-0 items-center gap-2 rounded-tile hover:text-accent transition-colors"
    >
      <Avatar name={name} src={person?.avatar_url} size={size} />
      <span className="min-w-0">
        <span className="block truncate text-[13px] font-semibold">{name}</span>
        {detail && <span className="block truncate text-[11.5px] text-subtle">{detail}</span>}
      </span>
    </Link>
  );
}

/** An institution's name, linking to everything about it. */
export function InstitutionChip({ id, institution, size = 26 }) {
  if (!id) return <span className="text-subtle">—</span>;
  const name = institution?.name ?? 'Deleted institution';
  return (
    <Link
      to={`/admin/institutions/${id}`}
      onClick={(e) => e.stopPropagation()}
      className="inline-flex min-w-0 items-center gap-2 hover:text-accent transition-colors"
    >
      <Avatar name={name} src={institution?.logo_url} size={size} className="rounded-[8px]" />
      <span className="truncate text-[13px] font-semibold">{name}</span>
    </Link>
  );
}

/** Loading, error and empty, so every list handles all three the same way. */
export function DataState({ loading, error, empty, emptyIcon, emptyTitle, emptySubtitle, children }) {
  if (loading) return <Loading label="Loading" />;
  if (error) return <Alert tone="error">{error}</Alert>;
  if (empty) {
    return (
      <EmptyState icon={emptyIcon} title={emptyTitle ?? 'Nothing here'} subtitle={emptySubtitle} />
    );
  }
  return children;
}

/** A titled card section. */
export function Section({ title, count, action, className = '', children }) {
  return (
    <SurfaceCard className={`p-5 ${className}`}>
      {(title || action) && (
        <div className="mb-3 flex items-center justify-between gap-3">
          <h3 className="text-[14px] font-bold">
            {title}
            {count != null && <span className="ml-1.5 font-medium text-subtle">{count}</span>}
          </h3>
          {action}
        </div>
      )}
      {children}
    </SurfaceCard>
  );
}

/** Label / value pairs in a responsive grid. Empty values show a dash. */
export function Details({ items }) {
  return (
    <dl className="grid grid-cols-1 gap-x-8 gap-y-3 sm:grid-cols-2 2xl:grid-cols-3">
      {items.filter(Boolean).map(([label, value]) => (
        <div key={label} className="min-w-0">
          <dt className="text-[11px] font-bold uppercase tracking-[1px] text-subtle">{label}</dt>
          <dd className="mt-0.5 break-words text-[13.5px]">
            {value === null || value === undefined || value === '' ? (
              <span className="text-subtle">—</span>
            ) : value}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/** A short list of words as pills. */
export function Pills({ values, empty = '—' }) {
  const list = (values ?? []).filter(Boolean);
  if (list.length === 0) return <span className="text-subtle">{empty}</span>;
  return (
    <span className="flex flex-wrap gap-1.5">
      {list.map((v) => <Badge key={v} compact>{v}</Badge>)}
    </span>
  );
}

/** Paragraph text that keeps the author's line breaks. */
export function Prose({ children }) {
  if (!children) return <span className="text-subtle">—</span>;
  return <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed text-white/85">{children}</p>;
}
