import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  BookOpen,
  CalendarCheck,
  GraduationCap,
  Inbox,
  LayoutDashboard,
  LogOut,
  QrCode,
  Radio,
  Settings,
  Sparkles,
  Users,
  Workflow,
} from 'lucide-react';
import { VerifiedBadge } from '../../components/VerifiedBadge';
import { useAuth } from '../../context/AuthContext';
import { initials } from '../../lib/format';
import { INSTITUTION_TIERS } from '../../lib/vocab';

// Grouped rather than a flat list: with the profile, posts and Spaces added
// this passes a dozen items, and the three groups answer different questions —
// who is interested in us, what are we putting out, and how is the account set up.
const NAV = [
  {
    section: 'Audience',
    items: [
      { to: '/institution', label: 'Dashboard', icon: LayoutDashboard, end: true },
      { to: '/institution/students', label: 'Matched students', icon: Sparkles },
      { to: '/institution/pipeline', label: 'Pipeline', icon: Workflow },
      { to: '/institution/appointments', label: 'Appointments', icon: CalendarCheck },
      { to: '/institution/inbox', label: 'Inbox', icon: Inbox },
    ],
  },
  {
    section: 'Publish',
    items: [
      { to: '/institution/profile', label: 'Profile', icon: BookOpen },
      { to: '/institution/programs', label: 'Programs', icon: GraduationCap },
      { to: '/institution/spaces', label: 'Spaces', icon: Radio },
    ],
  },
  {
    section: 'Organisation',
    items: [
      { to: '/institution/fairs', label: 'Fairs', icon: QrCode },
      { to: '/institution/team', label: 'Team', icon: Users },
      { to: '/institution/settings', label: 'Settings', icon: Settings },
    ],
  },
];

const TITLES = {
  '/institution': 'Recruitment dashboard',
  '/institution/students': 'Students who match you',
  '/institution/profile': 'Your institution page',
  '/institution/programs': 'Your programs',
  '/institution/spaces': 'Live Spaces',
  '/institution/pipeline': 'Admission pipeline',
  '/institution/appointments': 'Appointments',
  '/institution/inbox': 'Inbox',
  '/institution/fairs': 'Education fairs',
  '/institution/team': 'Team',
  '/institution/settings': 'Settings',
};

export default function InstitutionShell() {
  const { institution, profile, signOut } = useAuth();
  const { pathname } = useLocation();

  return (
    <div className="aurora h-full flex">
      <nav className="w-[248px] shrink-0 flex flex-col border-r border-line/60 py-6 overflow-y-auto scrollbar-thin">
        <div className="px-5 flex items-center gap-3">
          <div className="size-10 rounded-tile gradient-accent grid place-items-center shrink-0">
            <GraduationCap size={20} className="text-on-accent" strokeWidth={2.2} />
          </div>
          <div className="min-w-0">
            <div className="font-bold leading-tight truncate">
              {institution?.name ?? 'Your institution'}
            </div>
            <div className="text-[12px] text-subtle">
              {INSTITUTION_TIERS[institution?.tier] ?? 'Basic'} plan
            </div>
          </div>
        </div>

        {institution && (
          <div className="px-5 mt-4">
            <VerifiedBadge
              subject="institution"
              status={institution.verification_status}
            />
          </div>
        )}

        <div className="mt-7 flex flex-col gap-5 px-3">
          {NAV.map(({ section, items }) => (
            <div key={section} className="flex flex-col gap-1">
              <div className="px-3 pb-1 text-[10.5px] font-bold uppercase tracking-[1.1px] text-white/35">
                {section}
              </div>
              {items.map(({ to, label, icon: Icon, end }) => (
                <NavLink
                  key={to}
                  to={to}
                  end={end}
                  className={({ isActive }) =>
                    `flex items-center gap-3 px-3 h-10 rounded-tile text-[13.5px] font-medium transition-colors ${
                      isActive
                        ? 'bg-accent/12 text-accent'
                        : 'text-muted hover:text-white hover:bg-white/5'
                    }`
                  }
                >
                  <Icon size={17} strokeWidth={2.1} />
                  {label}
                </NavLink>
              ))}
            </div>
          ))}
        </div>

        <div className="mt-auto px-3 pt-6">
          <div className="flex items-center gap-3 px-3 py-2">
            <div className="size-8 rounded-full bg-surface-variant grid place-items-center text-[12px] font-bold shrink-0">
              {initials(profile?.full_name)}
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-[13px] font-medium truncate">
                {profile?.full_name || 'You'}
              </div>
            </div>
            <button
              type="button"
              onClick={signOut}
              title="Sign out"
              className="text-muted hover:text-error cursor-pointer transition-colors"
            >
              <LogOut size={16} strokeWidth={2.1} />
            </button>
          </div>
        </div>
      </nav>

      <main className="flex-1 min-w-0 flex flex-col overflow-hidden">
        <header className="px-8 pt-7 pb-5 shrink-0">
          <h1 className="text-[24px] font-bold leading-tight">
            {TITLES[pathname] ?? 'Eduxfair'}
          </h1>
        </header>
        <div className="flex-1 min-h-0 overflow-y-auto scrollbar-thin px-8 pb-8">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
