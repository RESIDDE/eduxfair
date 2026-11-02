import { useParams } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { RoomShell } from '../../components/live';

/**
 * A 1:1 appointment, in a Lekkside room.
 *
 * Its chat panel reads the `messages` thread this student and institution
 * already have, so what is typed during the call is in the inbox afterwards.
 */
export default function AppointmentCallPage() {
  const { id } = useParams();
  const { profile } = useAuth();
  return (
    <RoomShell
      appointmentId={id}
      myProfileId={profile?.id}
      backTo="/institution/appointments"
      backLabel="Back to appointments"
    />
  );
}
