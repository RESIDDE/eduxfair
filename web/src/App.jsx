import { Navigate, Route, Routes } from 'react-router-dom';
import { Loading } from './components/ui';
import { useAuth } from './context/AuthContext';
import { isConfigured } from './lib/supabase';

import SignInPage from './routes/SignInPage';
import ConfigurationNotice from './routes/ConfigurationNotice';
/*
 * The institution console is NOT routed in this build.
 *
 * This app is the super admin console and nothing else: students and
 * institutions both live in the Lekkside Connect Flutter app. The pages under
 * routes/institution/ are deliberately left on disk rather than deleted,
 * because six of them have no Flutter equivalent yet — Matched students,
 * Appointments, Programs, Team, Fairs and Settings are all still
 * OrgComingSoonScreen stubs over there, and `programs` in particular is what
 * the whole matching engine reads. Re-enabling them is restoring the imports
 * and the isInstitution block below; deleting them would not be.
 */

/*
 * The in-browser call room is not routed here either, for the same reason as
 * the rest of the institution console: joining a Space or a meeting happens in
 * the Flutter app now. components/live/ and the two room pages stay on disk,
 * and the practical effect of unrouting them is that livekit-client — ~850 KB
 * of WebRTC machinery — no longer reaches this bundle at all.
 */

import AdminShell from './routes/admin/AdminShell';
import AdminOverviewPage from './routes/admin/AdminOverviewPage';
import AdminPeoplePage from './routes/admin/AdminPeoplePage';
import AdminModerationPage from './routes/admin/AdminModerationPage';
import AdminSpacesPage from './routes/admin/AdminSpacesPage';
import VerificationQueuePage from './routes/admin/VerificationQueuePage';
import AdminFairsPage from './routes/admin/AdminFairsPage';
import AdminInstitutionsPage from './routes/admin/AdminInstitutionsPage';
import AdminAnalyticsPage from './routes/admin/AdminAnalyticsPage';

export default function App() {
  const { loading, session, isAdmin } = useAuth();

  if (!isConfigured) return <ConfigurationNotice />;

  if (loading) {
    return (
      <div className="aurora h-full grid place-items-center">
        <Loading />
      </div>
    );
  }

  if (!session) {
    return (
      <Routes>
        <Route path="/signin" element={<SignInPage />} />
        {/* No marketing page: this console has exactly one audience, and it
            already knows what it is here for. */}
        <Route path="*" element={<Navigate to="/signin" replace />} />
      </Routes>
    );
  }

  // Anyone who is not an admin — a student, or institution staff who used to
  // sign in here before this became the admin console.
  if (!isAdmin) return <NotAnAdmin />;

  return (
    <Routes>
      <Route path="/admin" element={<AdminShell />}>
        {/* The queue used to be the index. It moved to its own path when the
            console grew a real overview, so the landing page can say what
            needs attention across all of them rather than only one. */}
        <Route index element={<AdminOverviewPage />} />
        <Route path="verification" element={<VerificationQueuePage />} />
        <Route path="moderation" element={<AdminModerationPage />} />
        <Route path="people" element={<AdminPeoplePage />} />
        <Route path="institutions" element={<AdminInstitutionsPage />} />
        <Route path="spaces" element={<AdminSpacesPage />} />
        <Route path="fairs" element={<AdminFairsPage />} />
        <Route path="analytics" element={<AdminAnalyticsPage />} />
      </Route>

      <Route path="*" element={<Navigate to="/admin" replace />} />
    </Routes>
  );
}

function NotAnAdmin() {
  const { signOut, profile } = useAuth();

  return (
    <div className="aurora h-full grid place-items-center px-6">
      <div className="max-w-md text-center">
        <h1 className="text-2xl font-bold">This is the super admin console</h1>
        <p className="mt-3 leading-relaxed text-muted">
          {profile?.full_name ? `${profile.full_name}, your` : 'Your'} account is
          not an administrator. Students and institutions use the Eduxfair
          app — everything you need is there, not here.
        </p>
        <button
          type="button"
          onClick={signOut}
          className="mt-6 h-11 cursor-pointer rounded-full gradient-accent px-6 font-semibold text-on-accent transition-[filter] hover:brightness-110"
        >
          Sign out
        </button>
      </div>
    </div>
  );
}
