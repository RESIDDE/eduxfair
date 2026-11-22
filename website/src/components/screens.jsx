// Recreations of real EduXFair screens, drawn on the 300 × 650 phone canvas.
// Labels, stages and seed data come from student_app (app_constants.dart,
// the screens under lib/features, and devserver/seed.mjs), so what the site
// shows is what the app does.

import {
  BadgeCheck,
  Bell,
  Bookmark,
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  FileText,
  GraduationCap,
  Heart,
  Home,
  Mail,
  MessageCircle,
  Mic,
  Plus,
  Podcast,
  Search,
  Send,
  ShieldCheck,
  Users,
  Video,
} from 'lucide-react';
import { StatusBar } from './Phone';

const ACCENT = '#0095f6';

function AppBar({ title, back = false, action }) {
  return (
    <div className="flex h-[44px] items-center gap-2 px-4">
      {back && <ChevronLeft size={22} strokeWidth={2.2} className="-ml-1" />}
      <span className="text-[19px] font-bold tracking-[-0.02em]">{title}</span>
      <span className="ml-auto">{action}</span>
    </div>
  );
}

function TabBar({ active = 0 }) {
  const items = [Home, Search, Podcast, Mail];
  return (
    <div className="absolute inset-x-3 bottom-4 flex h-[54px] items-center rounded-full bg-white/90 shadow-[0_6px_24px_rgba(0,0,0,0.12)] ring-1 ring-black/5 backdrop-blur">
      {items.map((Icon, i) => (
        <span key={i} className="flex flex-1 justify-center">
          <Icon size={22} strokeWidth={i === active ? 2.6 : 1.9} color={i === active ? '#000' : '#737373'} />
        </span>
      ))}
      <span className="flex flex-1 justify-center">
        <span className="grid h-[26px] w-[26px] place-items-center rounded-full bg-gradient-to-br from-[#1f6bff] to-[#0b2f7a] text-[10px] font-bold text-white">
          CO
        </span>
      </span>
    </div>
  );
}

function InstAvatar({ code, size = 32, ring = false, from = '#1f6bff', to = '#0b2f7a' }) {
  const inner = (
    <span
      className="grid place-items-center rounded-full font-bold text-white"
      style={{
        width: size,
        height: size,
        fontSize: size * 0.34,
        background: `linear-gradient(135deg, ${from}, ${to})`,
      }}
    >
      {code}
    </span>
  );
  if (!ring) return inner;
  return (
    <span
      className="grid place-items-center rounded-full p-[2px]"
      style={{ background: 'linear-gradient(45deg,#feda75,#fa7e1e,#d62976,#962fbf,#4f5bd5)' }}
    >
      <span className="grid place-items-center rounded-full bg-white p-[2px]">{inner}</span>
    </span>
  );
}

const INST = {
  maple: { name: 'Maplecrest University', short: 'MU', place: 'Toronto, Canada', from: '#d62e2e', to: '#7a0f1c' },
  north: { name: 'Northgate College London', short: 'NC', place: 'London, UK', from: '#1f6bff', to: '#0b2f7a' },
  lake: { name: 'Lakeshore State University', short: 'LS', place: 'Chicago, USA', from: '#0e9f6e', to: '#065f46' },
};

/* ── Feed (home) ───────────────────────────────────────────────────────── */
export function FeedScreen() {
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <div className="flex h-[44px] items-center px-4">
        <span className="text-[22px] font-bold tracking-[-0.04em]">
          Edu<span style={{ color: ACCENT }}>X</span>Fair
        </span>
        <span className="ml-auto flex gap-4">
          <Heart size={22} strokeWidth={1.9} />
          <MessageCircle size={22} strokeWidth={1.9} />
        </span>
      </div>
      <div className="flex gap-3 overflow-hidden px-3 pt-1 pb-3">
        {[
          ['Your story', null],
          ['maplecrest', INST.maple],
          ['northgate', INST.north],
          ['lakeshore', INST.lake],
          ['ukvisas', { short: 'UK', from: '#6b21a8', to: '#312e81' }],
        ].map(([label, inst], i) => (
          <span key={label} className="flex w-[52px] shrink-0 flex-col items-center gap-1">
            {inst ? (
              <InstAvatar code={inst.short} size={46} ring from={inst.from} to={inst.to} />
            ) : (
              <span className="relative grid h-[52px] w-[52px] place-items-center rounded-full bg-[#efefef] text-[13px] font-bold text-[#737373]">
                CO
                <span className="absolute right-0 bottom-0 grid h-[16px] w-[16px] place-items-center rounded-full border-2 border-white" style={{ background: ACCENT }}>
                  <Plus size={10} color="#fff" strokeWidth={3} />
                </span>
              </span>
            )}
            <span className="w-full truncate text-center text-[9.5px] text-[#262626]">{label}</span>
            {i === 0 && null}
          </span>
        ))}
      </div>
      <div className="border-t border-[#efefef]">
        <div className="flex items-center gap-2 px-3 py-2">
          <InstAvatar code="MU" size={28} from={INST.maple.from} to={INST.maple.to} />
          <span className="text-[12.5px] font-semibold">maplecrest</span>
          <BadgeCheck size={13} color="#fff" fill={ACCENT} />
          <span className="text-[12px] text-[#737373]">· 2h</span>
        </div>
        <div className="relative aspect-[4/5] w-full overflow-hidden" style={{ background: 'linear-gradient(160deg,#7a0f1c,#d62e2e 55%,#ff8a5b)' }}>
          <div className="absolute inset-0 opacity-25" style={{ backgroundImage: 'radial-gradient(circle at 20% 20%, #fff 0 1px, transparent 1.5px)', backgroundSize: '14px 14px' }} />
          <div className="absolute inset-x-5 top-6 text-white">
            <div className="text-[10px] font-semibold tracking-[0.14em] uppercase opacity-85">Open day · Live in the app</div>
            <div className="mt-2 text-[27px] leading-[1.02] font-bold tracking-[-0.04em]">Engineering at Maplecrest.</div>
            <div className="mt-2 text-[12px] leading-snug opacity-90">Tour the labs, meet the faculty and ask about co-op placements.</div>
          </div>
          <div className="absolute right-5 bottom-5 left-5 flex items-center gap-2 rounded-2xl bg-black/30 px-3 py-2 text-white backdrop-blur">
            <span className="h-2 w-2 rounded-full bg-[#ff3b30]" />
            <span className="text-[11.5px] font-semibold">Open day</span>
            <span className="ml-auto text-[11px] opacity-85">Saturday · 3:00 PM</span>
          </div>
        </div>
        <div className="flex items-center gap-4 px-3 pt-2.5">
          <Heart size={22} strokeWidth={1.9} fill="#ed4956" color="#ed4956" />
          <MessageCircle size={22} strokeWidth={1.9} />
          <Send size={21} strokeWidth={1.9} />
          <Bookmark size={21} strokeWidth={1.9} className="ml-auto" />
        </div>
        <div className="px-3 pt-1.5 text-[12px]"><b>214 likes</b></div>
      </div>
      <TabBar active={0} />
    </div>
  );
}

/* ── Passport ──────────────────────────────────────────────────────────── */
export function PassportScreen() {
  const docs = [
    ['Academic transcript', true],
    ['English test result', true],
    ['Passport or national ID', true],
    ['Personal statement', false],
  ];
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <AppBar title="My Passport" action={<ShieldCheck size={20} />} />
      <div className="px-4">
        <div className="relative overflow-hidden rounded-[22px] p-4 text-white" style={{ background: 'linear-gradient(140deg,#061a47,#0b2f7a 55%,#1f6bff)' }}>
          <div className="absolute -top-10 -right-10 h-32 w-32 rounded-full bg-white/10" />
          <div className="flex items-center gap-3">
            <span className="grid h-[46px] w-[46px] place-items-center rounded-full bg-white/15 text-[15px] font-bold ring-2 ring-white/40">CO</span>
            <div>
              <div className="flex items-center gap-1 text-[16px] font-bold tracking-[-0.02em]">
                Chidi Okeke <BadgeCheck size={15} color="#0b2f7a" fill="#fff" />
              </div>
              <div className="text-[11.5px] opacity-80">Lagos, Nigeria · Undergraduate</div>
            </div>
          </div>
          <div className="mt-4 flex items-center justify-between text-[11px]">
            <span className="opacity-85">Passport complete</span>
            <span className="font-semibold">86%</span>
          </div>
          <div className="mt-1.5 h-[5px] rounded-full bg-white/20">
            <div className="h-full w-[86%] rounded-full bg-white" />
          </div>
        </div>

        <div className="mt-4 text-[15px] font-bold tracking-[-0.02em]">Academics</div>
        <div className="mt-2 grid grid-cols-2 gap-2">
          {[
            ['WAEC / NECO', '7 credits · A1–B3'],
            ['IELTS', 'Overall 7.0'],
            ['Field', 'Computer Science'],
            ['Budget', 'Up to $25,000'],
          ].map(([k, v]) => (
            <div key={k} className="rounded-[14px] bg-[#f5f5f5] px-3 py-2.5">
              <div className="text-[10px] font-medium text-[#737373]">{k}</div>
              <div className="mt-0.5 text-[12.5px] font-semibold tracking-[-0.01em]">{v}</div>
            </div>
          ))}
        </div>

        <div className="mt-4 flex items-center text-[15px] font-bold tracking-[-0.02em]">
          Documents <span className="ml-auto text-[12px] font-semibold" style={{ color: ACCENT }}>Add</span>
        </div>
        <div className="mt-1.5 divide-y divide-[#efefef]">
          {docs.map(([d, ok]) => (
            <div key={d} className="flex items-center gap-3 py-2.5">
              <span className="grid h-[30px] w-[30px] place-items-center rounded-[9px] bg-[#e7f3ff]">
                <FileText size={15} color={ACCENT} />
              </span>
              <span className="text-[12.5px] font-medium">{d}</span>
              {ok ? (
                <span className="ml-auto grid h-[18px] w-[18px] place-items-center rounded-full bg-[#0e9f6e]">
                  <Check size={11} color="#fff" strokeWidth={3} />
                </span>
              ) : (
                <span className="ml-auto text-[11px] text-[#737373]">Missing</span>
              )}
            </div>
          ))}
        </div>
      </div>
      <TabBar active={4} />
    </div>
  );
}

/* ── Matches ───────────────────────────────────────────────────────────── */
function MatchRing({ value, size = 44 }) {
  const r = (size - 6) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span className="relative grid place-items-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} stroke="#efefef" strokeWidth="4" fill="none" />
        <circle cx={size / 2} cy={size / 2} r={r} stroke={ACCENT} strokeWidth="4" fill="none" strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - value / 100)} />
      </svg>
      <span className="absolute text-[11.5px] font-bold">{value}%</span>
    </span>
  );
}

export function MatchesScreen() {
  const items = [
    [INST.maple, 'BSc Computer Science', 'Undergraduate · 4 years', 94],
    [INST.north, 'MSc Computing', 'Postgraduate · 1 year', 88],
    [INST.lake, 'BS Cybersecurity', 'Undergraduate · 4 years', 81],
  ];
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <AppBar title="Matches" action={<Bell size={20} />} />
      <div className="px-4">
        <div className="rounded-[18px] border border-[#dbdbdb] p-3">
          <div className="flex items-center gap-2.5">
            <InstAvatar code="MU" size={34} from={INST.maple.from} to={INST.maple.to} />
            <div className="text-[12px] leading-snug">
              <b>Maplecrest University</b> would like to see your passport.
            </div>
          </div>
          <div className="mt-2.5 flex gap-2">
            <span className="flex-1 rounded-[10px] bg-[#efefef] py-[7px] text-center text-[12px] font-semibold">Not now</span>
            <span className="flex-1 rounded-[10px] py-[7px] text-center text-[12px] font-semibold text-white" style={{ background: ACCENT }}>Share</span>
          </div>
        </div>
        <div className="mt-4 mb-2 text-[12px] font-semibold text-[#737373]">Programs that fit your passport</div>
        <div className="space-y-2.5">
          {items.map(([inst, prog, meta, pct]) => (
            <div key={prog} className="flex items-center gap-3 rounded-[18px] bg-[#f5f5f5] p-3">
              <MatchRing value={pct} />
              <div className="min-w-0 flex-1">
                <div className="truncate text-[13px] font-bold tracking-[-0.01em]">{prog}</div>
                <div className="truncate text-[11px] text-[#737373]">{inst.name}</div>
                <div className="text-[10.5px] text-[#737373]">{meta}</div>
              </div>
              <ChevronRight size={16} color="#a8a8a8" />
            </div>
          ))}
        </div>
      </div>
      <TabBar active={1} />
    </div>
  );
}

/* ── Meet: appointments + live spaces ──────────────────────────────────── */
export function MeetScreen() {
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <AppBar title="My meetings" back />
      <div className="px-4">
        <div className="text-[15px] font-bold tracking-[-0.02em]">Upcoming</div>
        <div className="mt-2 rounded-[18px] border border-[#dbdbdb] p-3.5">
          <div className="flex items-center gap-2.5">
            <InstAvatar code="MU" size={36} from={INST.maple.from} to={INST.maple.to} />
            <div>
              <div className="text-[13px] font-bold tracking-[-0.01em]">Admissions one-to-one</div>
              <div className="text-[11px] text-[#737373]">Maplecrest University</div>
            </div>
          </div>
          <div className="mt-3 flex items-center gap-2 text-[11.5px] text-[#262626]">
            <CalendarDays size={14} /> Thursday · 2:00 PM
            <span className="ml-auto flex items-center gap-1 text-[#737373]"><Video size={13} /> Video</span>
          </div>
          <div className="mt-3 rounded-[10px] py-[8px] text-center text-[12px] font-semibold text-white" style={{ background: ACCENT }}>
            Join meeting
          </div>
        </div>

        <div className="mt-5 flex items-center text-[15px] font-bold tracking-[-0.02em]">
          Live spaces
          <span className="ml-2 flex items-center gap-1 rounded-full bg-[#fdecee] px-2 py-[2px] text-[10px] font-bold text-[#ed4956]">
            <span className="h-1.5 w-1.5 rounded-full bg-[#ed4956]" /> LIVE
          </span>
        </div>
        <div className="mt-2 overflow-hidden rounded-[18px] text-white" style={{ background: 'linear-gradient(140deg,#0b2f7a,#1f6bff)' }}>
          <div className="p-3.5">
            <div className="text-[10px] font-semibold tracking-[0.12em] uppercase opacity-80">Scholarship Q&amp;A</div>
            <div className="mt-1 text-[15px] leading-tight font-bold tracking-[-0.02em]">Funding, awards and who qualifies</div>
            <div className="mt-3 flex items-center">
              <span className="flex -space-x-2">
                {['#d62e2e', '#0e9f6e', '#f59e0b', '#6b21a8'].map((c) => (
                  <span key={c} className="h-6 w-6 rounded-full ring-2 ring-[#1f6bff]" style={{ background: c }} />
                ))}
              </span>
              <span className="ml-2 text-[11px] opacity-90">128 listening</span>
              <span className="ml-auto grid h-8 w-8 place-items-center rounded-full bg-white/20"><Mic size={15} /></span>
            </div>
          </div>
        </div>
        <div className="mt-2.5 flex items-center gap-3 rounded-[18px] bg-[#f5f5f5] p-3">
          <span className="grid h-9 w-9 place-items-center rounded-[11px] bg-white"><Users size={17} /></span>
          <div>
            <div className="text-[12.5px] font-semibold">Country briefing: studying in the UK</div>
            <div className="text-[11px] text-[#737373]">Northgate College London · Tomorrow</div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Applications ──────────────────────────────────────────────────────── */
export function ApplicationsScreen() {
  const stages = ['Submitted', 'Under review', 'Conditional offer', 'Offer'];
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <AppBar title="My applications" back />
      <div className="px-4">
        <div className="text-[15px] font-bold tracking-[-0.02em]">In progress</div>
        <div className="mt-2 rounded-[18px] border border-[#dbdbdb] p-3.5">
          <div className="flex items-center gap-2.5">
            <InstAvatar code="MU" size={36} from={INST.maple.from} to={INST.maple.to} />
            <div className="min-w-0">
              <div className="truncate text-[13px] font-bold tracking-[-0.01em]">BSc Computer Science</div>
              <div className="text-[11px] text-[#737373]">Maplecrest University</div>
            </div>
          </div>
          <div className="mt-3 inline-flex items-center gap-1 rounded-full bg-[#def7ec] px-2.5 py-1 text-[11px] font-semibold text-[#0e9f6e]">
            <GraduationCap size={13} /> Conditional offer
          </div>
          <div className="mt-3.5 space-y-0">
            {stages.map((s, i) => {
              const done = i < 2;
              const now = i === 2;
              return (
                <div key={s} className="flex items-start gap-2.5">
                  <div className="flex flex-col items-center">
                    <span
                      className="grid h-[18px] w-[18px] place-items-center rounded-full"
                      style={{ background: done ? ACCENT : now ? '#fff' : '#efefef', boxShadow: now ? `inset 0 0 0 2px ${ACCENT}` : undefined }}
                    >
                      {done && <Check size={11} color="#fff" strokeWidth={3} />}
                    </span>
                    {i < stages.length - 1 && <span className="h-[18px] w-[2px]" style={{ background: done ? ACCENT : '#efefef' }} />}
                  </div>
                  <span className={`text-[12px] ${now ? 'font-bold' : done ? 'font-medium' : 'text-[#a8a8a8]'}`}>{s}</span>
                  {now && <span className="ml-auto text-[10.5px] font-semibold" style={{ color: ACCENT }}>Now</span>}
                </div>
              );
            })}
          </div>
        </div>
        <div className="mt-2.5 rounded-[18px] border border-[#dbdbdb] p-3.5">
          <div className="flex items-center gap-2.5">
            <InstAvatar code="NC" size={36} from={INST.north.from} to={INST.north.to} />
            <div className="min-w-0">
              <div className="truncate text-[13px] font-bold tracking-[-0.01em]">MSc Computing</div>
              <div className="text-[11px] text-[#737373]">Northgate College London</div>
            </div>
          </div>
          <div className="mt-2.5 flex items-center gap-2">
            <span className="rounded-full bg-[#fef3c7] px-2.5 py-1 text-[11px] font-semibold text-[#b45309]">Documents requested</span>
            <span className="ml-auto text-[11px] font-semibold" style={{ color: ACCENT }}>Upload</span>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Fair Passport (QR) ────────────────────────────────────────────────── */
function FakeQr({ size = 140 }) {
  // A deterministic pattern with the three finder squares. Decorative only.
  const n = 25;
  const cell = size / n;
  const cells = [];
  let seed = 7;
  const rnd = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
  const finder = (x, y) => x < 7 && y < 7 || x >= n - 7 && y < 7 || x < 7 && y >= n - 7;
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++) if (!finder(x, y) && rnd() > 0.52) cells.push([x, y]);
  const Finder = ({ x, y }) => (
    <g transform={`translate(${x * cell} ${y * cell})`}>
      <rect width={cell * 7} height={cell * 7} rx={cell * 1.6} fill="#000" />
      <rect x={cell} y={cell} width={cell * 5} height={cell * 5} rx={cell * 1.1} fill="#fff" />
      <rect x={cell * 2} y={cell * 2} width={cell * 3} height={cell * 3} rx={cell * 0.8} fill="#000" />
    </g>
  );
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      {cells.map(([x, y]) => (
        <rect key={`${x}-${y}`} x={x * cell + 0.4} y={y * cell + 0.4} width={cell - 0.8} height={cell - 0.8} rx={cell * 0.3} fill="#000" />
      ))}
      <Finder x={0} y={0} />
      <Finder x={n - 7} y={0} />
      <Finder x={0} y={n - 7} />
    </svg>
  );
}

export function FairPassportScreen() {
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <AppBar title="Fair Passport" back />
      <div className="px-4">
        <div className="rounded-[22px] p-4 text-center text-white" style={{ background: 'linear-gradient(150deg,#061a47,#0b2f7a 60%,#1f6bff)' }}>
          <div className="text-[10px] font-semibold tracking-[0.14em] uppercase opacity-80">Lagos Education Fair</div>
          <div className="mt-0.5 text-[15px] font-bold tracking-[-0.02em]">Show this at any booth</div>
          <div className="mx-auto mt-3 w-fit rounded-[16px] bg-white p-3">
            <FakeQr size={128} />
          </div>
          <div className="mt-2.5 text-[11px] opacity-85">Chidi Okeke · Registered</div>
        </div>
        <div className="mt-4 text-[14px] font-bold tracking-[-0.02em]">Booths you have connected with</div>
        <div className="mt-1.5 divide-y divide-[#efefef]">
          {[
            [INST.maple, 'A01', '11:24'],
            [INST.north, 'A02', '12:05'],
          ].map(([inst, booth, t]) => (
            <div key={booth} className="flex items-center gap-2.5 py-2.5">
              <InstAvatar code={inst.short} size={30} from={inst.from} to={inst.to} />
              <div>
                <div className="text-[12.5px] font-semibold">{inst.name}</div>
                <div className="text-[10.5px] text-[#737373]">Booth {booth} · {t}</div>
              </div>
              <Check size={16} className="ml-auto" color="#0e9f6e" strokeWidth={2.6} />
            </div>
          ))}
        </div>
        <div className="mt-2 rounded-[12px] bg-[#efefef] py-[9px] text-center text-[12.5px] font-semibold">My fair report</div>
      </div>
    </div>
  );
}

/* ── Institution dashboard (staff shell) ───────────────────────────────── */
export function OrgDashboardScreen() {
  return (
    <div className="relative h-full bg-white text-black">
      <StatusBar />
      <AppBar title="Maplecrest" action={<Bell size={20} />} />
      <div className="px-4">
        <div className="grid grid-cols-3 gap-2">
          {[
            ['Matched', '442'],
            ['Shared', '37'],
            ['Applied', '12'],
          ].map(([k, v]) => (
            <div key={k} className="rounded-[14px] bg-[#f5f5f5] px-2.5 py-2.5">
              <div className="text-[18px] font-bold tracking-[-0.03em]">{v}</div>
              <div className="text-[10px] text-[#737373]">{k}</div>
            </div>
          ))}
        </div>
        <div className="mt-4 text-[14px] font-bold tracking-[-0.02em]">Students who fit</div>
        <div className="mt-1.5 space-y-2">
          {[
            ['Student · Lagos', 'BSc Computer Science', 94],
            ['Student · Abuja', 'MSc Data Science', 91],
            ['Student · Port Harcourt', 'BEng Mechanical', 87],
          ].map(([who, prog, pct]) => (
            <div key={who} className="flex items-center gap-2.5 rounded-[14px] border border-[#efefef] p-2.5">
              <span className="h-8 w-8 rounded-full bg-gradient-to-br from-[#dbdbdb] to-[#a8a8a8] blur-[1.5px]" />
              <div className="min-w-0 flex-1">
                <div className="text-[12px] font-semibold">{who}</div>
                <div className="truncate text-[10.5px] text-[#737373]">{prog}</div>
              </div>
              <span className="text-[11.5px] font-bold" style={{ color: ACCENT }}>{pct}%</span>
            </div>
          ))}
        </div>
        <div className="mt-3 rounded-[10px] py-[8px] text-center text-[12px] font-semibold text-white" style={{ background: ACCENT }}>
          Invite to share
        </div>
      </div>
    </div>
  );
}
