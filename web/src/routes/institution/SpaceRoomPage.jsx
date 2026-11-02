import { useParams } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { RoomShell } from '../../components/live';

/** A Space, hosted from the console. Full-bleed, outside InstitutionShell. */
export default function SpaceRoomPage() {
  const { id } = useParams();
  const { profile } = useAuth();
  return (
    <RoomShell
      spaceId={id}
      myProfileId={profile?.id}
      backTo="/institution/spaces"
      backLabel="Back to Spaces"
    />
  );
}
