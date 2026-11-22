import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import {
  ArrowLeft,
  Building2,
  CalendarClock,
  ChartNoAxesColumn,
  FileStack,
  FileText,
  Flag,
  LayoutDashboard,
  LogOut,
  MessagesSquare,
  Newspaper,
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
    // Everything that happens on the platform, across every account — the
    // same lists the person and institution pages show, unfiltered.
    section: 'Activity',
    items: [
      { to: '/admin/posts', label: 'Posts & comments', icon: Newspaper },
      { to: '/admin/messages', label: 'Messages', icon: MessagesSquare },
      { to: '/admin/applications', label: 'Applications', icon: FileStack },
      { to: '/admin/documents', label: 'Documents', icon: FileText },
      { to: '/admin/meetings', label: 'Meetings', icon: CalendarClock },
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
  '/admin/posts': 'Posts and comments',
  '/admin/messages': 'Messages',
  '/admin/applications': 'Applications',
  '/admin/documents': 'Student documents',
  '/admin/meetings': 'Meetings',
};

/** Detail pages carry an id, so they are titled by prefix. */
const titleFor = (pathname) => {
  if (TITLES[pathname]) return TITLES[pathname];
  if (pathname.startsWith('/admin/people/')) return 'Account';
  if (pathname.startsWith('/admin/institutions/')) return 'Institution';
  return 'Eduxfair admin';
};

/**
 * Where "up" is from a page, when there is no earlier page to go back to: a
 * person goes up to People, an institution to Institutions, and every other
 * page to the Overview.
 */
const parentOf = (pathname) => {
  if (pathname.startsWith('/admin/people/')) return '/admin/people';
  if (pathname.startsWith('/admin/institutions/')) return '/admin/institutions';
  return '/admin';
};

/**
 * Whether this tab has an earlier page *in this console* to return to.
 *
 * React Router numbers its history entries in `history.state.idx`, starting at
 * 0 for the first page of the session; a redirect replaces rather than adds.
 * So idx > 0 means "Back" stays inside the console. Going back from idx 0
 * would leave the app entirely — to whatever site was open before it.
 */
const hasEarlierPage = () => (window.history.state?.idx ?? 0) > 0;

export default function AdminShell() {
  const { profile, signOut } = useAuth();
  const { pathname } = useLocation();
  const navigate = useNavigate();

  // On every page but the Overview, which is the top of the console.
  const showBack = pathname !== '/admin' || hasEarlierPage();

  // Back to where you came from — a report, a conversation, a list — rather
  // than to a fixed parent, which is what the old in-page links did. Up a
  // level only when there is nowhere to go back to: a bookmark, a pasted
  // link, or the first page after signing in.
  function goBack() {
    if (hasEarlierPage()) navigate(-1);
    else navigate(parentOf(pathname));
  }

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
        <header className="px-8 pt-7 pb-5 shrink-0 flex items-center gap-3">
          {showBack && (
            <button
              type="button"
              onClick={goBack}
              aria-label="Back"
              title="Back"
              className="-ml-2 grid size-9 shrink-0 place-items-center rounded-full text-muted transition-colors hover:bg-white/8 hover:text-white active:scale-95 cursor-pointer"
            >
              <ArrowLeft size={20} strokeWidth={2.2} />
            </button>
          )}
          <h1 className="text-[24px] font-bold leading-tight">
            {titleFor(pathname)}
          </h1>
        </header>
        <div className="flex-1 min-h-0 overflow-y-auto scrollbar-thin px-8 pb-8">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
