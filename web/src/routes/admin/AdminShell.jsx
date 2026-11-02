import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  Building2,
  ChartNoAxesColumn,
  Flag,
  LayoutDashboard,
  LogOut,
  QrCode,
  Radio,
  ShieldCheck,
  Users,
} from 'lucide-react';
import { useAuth } from '../../context/AuthContext';
import { initials } from '../../lib/format';

// Grouped, because a flat list of eight stops being scannable and these answer
// three different questions: what needs me now, who is on the platform, and how
// is it going. The order is the order of a shift — the queues first.
const NAV = [
  {
    section: 'Today',
    items: [
      { to: '/admin', label: 'Overview', icon: LayoutDashboard, end: true },
      { to: '/admin/verification', label: 'Verification queue', icon: ShieldCheck },
      { to: '/admin/moderation', label: 'Reports', icon: Flag },
    ],
  },
  {
    section: 'The platform',
    items: [
      { to: '/admin/people', label: 'People', icon: Users },
      { to: '/admin/institutions', label: 'Institutions', icon: Building2 },
      { to: '/admin/spaces', label: 'Live Spaces', icon: Radio },
      { to: '/admin/fairs', label: 'Fairs', icon: QrCode },
    ],
  },
  {
    section: 'Insight',
    items: [
      { to: '/admin/analytics', label: 'Analytics', icon: ChartNoAxesColumn },
    ],
  },
];

const TITLES = {
  '/admin': 'Overview',
  '/admin/verification': 'Verification queue',
  '/admin/moderation': 'Reports',
  '/admin/people': 'People',
  '/admin/institutions': 'Institutions',
  '/admin/spaces': 'Live Spaces',
  '/admin/fairs': 'Fairs and exhibitors',
  '/admin/analytics': 'Platform analytics',
};

export default function AdminShell() {
  const { profile, signOut } = useAuth();
  const { pathname } = useLocation();

  return (
    <div className="aurora h-full flex">
      <nav className="w-[232px] shrink-0 flex flex-col border-r border-line/60 py-6">
        <div className="px-5 flex items-center gap-3">
          <img
            src="/logo.png"
            alt="Eduxfair"
            className="size-10 rounded-tile object-contain bg-white p-0.5 shrink-0 shadow-sm"
          />
          <div className="min-w-0">
            <div className="font-bold leading-tight">Eduxfair</div>
            <div className="text-[12px] text-subtle">Super admin</div>
          </div>
        </div>

        <div className="mt-7 flex flex-col gap-5 px-3 overflow-y-auto scrollbar-thin">
          {NAV.map(({ section, items }) => (
            <div key={section} className="flex flex-col gap-1">
              <div className="px-3 pb-1 text-[10.5px] font-bold uppercase tracking-[1.1px] text-subtle">
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
                {profile?.full_name || 'Admin'}
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
            {TITLES[pathname] ?? 'Eduxfair admin'}
          </h1>
        </header>
        <div className="flex-1 min-h-0 overflow-y-auto scrollbar-thin px-8 pb-8">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
