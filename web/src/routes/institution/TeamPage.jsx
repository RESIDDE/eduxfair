import { useState } from 'react';
import { Trash2, Users } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  EmptyRow,
  Loading,
  TableCard,
  Td,
  Th,
  Toolbar,
  Tr,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDate } from '../../lib/format';
import { INSTITUTION_TIERS } from '../../lib/vocab';

/**
 * Admissions officer seats.
 *
 * Adding and removing seats is an owner action, enforced by the
 * `institution_members_insert_owner` policy. Seat limits come from the
 * subscription, and `institutions.tier` is not writable from here — a guard
 * trigger blocks it, so an institution cannot upgrade itself for free.
 */
export default function TeamPage() {
  const { institutionId, institution, isOwner, user } = useAuth();
  const [actionError, setActionError] = useState(null);

  const { data: members, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('institution_members')
        .select('id, member_role, created_at, profile_id, profiles(id, full_name)')
        .eq('institution_id', institutionId)
        .order('created_at'),
    [institutionId],
  );

  const { data: subscription } = useQuery(
    (client) =>
      client
        .from('institution_subscriptions')
        .select('*')
        .eq('institution_id', institutionId)
        .maybeSingle(),
    [institutionId],
  );

  async function removeSeat(member) {
    setActionError(null);
    const { error: writeError } = await supabase
      .from('institution_members')
      .delete()
      .eq('id', member.id);

    if (writeError) {
      setActionError(describeError(writeError));
      return;
    }
    reload();
  }

  if (loading) return <Loading label="Loading your team" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = members ?? [];
  const seats = subscription?.seats ?? 1;

  return (
    <div className="flex flex-col gap-4">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <Toolbar
        summary={`${rows.length} of ${seats} seat${seats === 1 ? '' : 's'} used · ${
          INSTITUTION_TIERS[institution?.tier] ?? 'Basic'
        } plan`}
      />

      <Alert tone="success">
        Colleagues join by signing up at this console with an institution
        account, then you add them here. Seat limits come from your plan — get
        in touch with Eduxfair to change it.
      </Alert>

      <TableCard minWidth={620}>
        <thead>
          <tr>
            <Th>Name</Th>
            <Th>Role</Th>
            <Th>Added</Th>
            <Th />
          </tr>
        </thead>
        <tbody>
          {rows.map((member) => (
            <Tr key={member.id}>
              <Td className="font-semibold">
                {member.profiles?.full_name || 'Pending'}
                {member.profile_id === user?.id && (
                  <span className="ml-2 text-[12px] text-subtle">(you)</span>
                )}
              </Td>
              <Td>
                <Badge tone={member.member_role === 'owner' ? 'live' : 'neutral'} compact>
                  {member.member_role === 'owner' ? 'Owner' : 'Admissions officer'}
                </Badge>
              </Td>
              <Td>{formatDate(member.created_at)}</Td>
              <Td>
                {isOwner && member.member_role !== 'owner' && (
                  <Button
                    size="sm"
                    variant="dangerGhost"
                    icon={Trash2}
                    onClick={() => removeSeat(member)}
                    title="Remove seat"
                  />
                )}
              </Td>
            </Tr>
          ))}
          {rows.length === 0 && (
            <EmptyRow colSpan={4} icon={Users}>
              No team members
            </EmptyRow>
          )}
        </tbody>
      </TableCard>
    </div>
  );
}
