import { useState } from 'react';
import { BadgeCheck, Check, EyeOff, FileText, GraduationCap, IdCard, Languages, Lock } from 'lucide-react';
import Reveal from '../components/Reveal';

const WAYS = [
  {
    name: 'Discover',
    blurb: 'Browse institutions and programs on your own terms.',
    big: 'A–Z',
    unit: 'programs, by level and field',
    points: ['Universities, colleges and embassies', 'Foundation to PhD', 'Scholarships with their deadlines'],
  },
  {
    name: 'Get matched',
    badge: 'Most loved',
    dark: true,
    blurb: 'Institutions that fit your passport come to you.',
    big: 'You',
    unit: 'decide who sees your name',
    points: ['Everything in Discover', 'Matched on grades, English and budget', 'Invitations you accept or decline'],
  },
  {
    name: 'Fair day',
    badge: 'In person',
    blurb: 'Walk the hall with your whole passport in your pocket.',
    big: '1 tap',
    unit: 'to connect at any booth',
    points: ['Everything in Get matched', 'A QR Fair Passport', 'A report of every booth you met'],
  },
];

function WayCard({ way, i }) {
  const d = way.dark;
  return (
    <Reveal
      delay={i * 90}
      className={`flex flex-col rounded-[28px] p-8 md:p-9 ${d ? 'bg-black text-white' : 'bg-white text-text'}`}
    >
      <div className="flex items-start justify-between gap-3">
        <h3 className="text-[28px] font-semibold tracking-[-0.03em]">{way.name}</h3>
        {way.badge && (
          <span
            className={`mt-1.5 rounded-full px-2.5 py-1 text-[12px] font-semibold ${
              d ? 'bg-brand text-white' : 'bg-ink text-white'
            }`}
          >
            {way.badge}
          </span>
        )}
      </div>
      <p className={`mt-1.5 text-[17px] ${d ? 'text-white/60' : 'text-mute-2'}`}>{way.blurb}</p>
      <div className="mt-12 flex items-baseline gap-2.5">
        <span className="shrink-0 text-[64px] leading-none font-semibold tracking-[-0.05em] whitespace-nowrap">{way.big}</span>
        <span className={`text-[17px] ${d ? 'text-white/55' : 'text-mute-2'}`}>{way.unit}</span>
      </div>
      <div className={`my-7 h-px ${d ? 'bg-white/15' : 'bg-line'}`} />
      <ul className="space-y-3">
        {way.points.map((p) => (
          <li key={p} className="flex items-start gap-3 text-[15px]">
            <Check size={17} className="mt-0.5 shrink-0 text-brand" strokeWidth={2.4} />
            {p}
          </li>
        ))}
      </ul>
      <div className={`mt-auto pt-10 text-[15px] ${d ? 'text-white/55' : 'text-mute-2'}`}>
        <span className={`text-[20px] font-semibold tracking-[-0.02em] ${d ? 'text-white' : 'text-text'}`}>Free</span>{' '}
        for students
      </div>
    </Reveal>
  );
}

/** What an institution sees before and after a student shares. */
function PrivacyCard() {
  const [shared, setShared] = useState(false);
  return (
    <Reveal className="flex flex-col rounded-[28px] bg-white p-8 md:p-10 lg:col-span-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="eyebrow">Privacy</p>
          <h3 className="headline mt-1.5 text-[clamp(1.9rem,3vw,2.6rem)]">Anonymous or shared.</h3>
        </div>
        <div role="tablist" aria-label="What an institution sees" className="flex rounded-full bg-cloud p-1 text-[14px]">
          {[
            [false, 'Matched'],
            [true, 'Shared'],
          ].map(([v, label]) => (
            <button
              key={label}
              role="tab"
              type="button"
              aria-selected={shared === v}
              onClick={() => setShared(v)}
              className={`rounded-full px-4 py-2 font-medium transition-all ${
                shared === v ? 'bg-white text-text shadow-sm' : 'text-mute-2 hover:text-text'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {/* The card an admissions officer sees */}
      <div className="relative mt-10 flex flex-1 items-center justify-center">
        <div className="w-full max-w-[460px] rounded-[22px] border border-line bg-white p-5 shadow-[0_30px_60px_-30px_rgba(0,0,0,0.25)]">
          <div className="flex items-center gap-3.5">
            <div className="relative">
              <span
                className={`grid h-14 w-14 place-items-center rounded-full bg-gradient-to-br from-brand to-navy text-[18px] font-bold text-white transition-all duration-500 ${
                  shared ? '' : 'blur-[6px] grayscale'
                }`}
              >
                CO
              </span>
              {!shared && (
                <span className="absolute inset-0 grid place-items-center">
                  <EyeOff size={18} className="text-mute-2" />
                </span>
              )}
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 text-[18px] font-semibold tracking-[-0.02em]">
                <span className={`transition-all duration-500 ${shared ? '' : 'rounded bg-cloud text-transparent select-none'}`}>
                  Chidi Okeke
                </span>
                {shared && <BadgeCheck size={17} className="text-brand" />}
              </div>
              <div className="text-[14px] text-mute-2">Lagos, Nigeria · Undergraduate</div>
            </div>
            <span className="ml-auto rounded-full bg-brand-soft px-3 py-1 text-[13px] font-semibold text-brand">94%</span>
          </div>
          <div className="mt-5 grid grid-cols-3 gap-2 text-[13px]">
            {[
              ['Field', 'Computer Science'],
              ['Grades', 'WAEC · 7 credits'],
              ['English', 'IELTS 7.0'],
            ].map(([k, v]) => (
              <div key={k} className="rounded-xl bg-cloud px-3 py-2.5">
                <div className="text-[11px] text-mute-2">{k}</div>
                <div className="mt-0.5 font-medium">{v}</div>
              </div>
            ))}
          </div>
          <div className="mt-3 flex items-center gap-2 rounded-xl border border-dashed border-line px-3 py-2.5 text-[13px]">
            {shared ? (
              <>
                <FileText size={15} className="text-brand" /> 3 documents shared
                <span className="ml-auto text-mute-2">Revocable any time</span>
              </>
            ) : (
              <>
                <Lock size={15} className="text-mute-2" /> Documents locked
                <span className="ml-auto text-mute-2">Invite to share</span>
              </>
            )}
          </div>
        </div>
      </div>
      <p className="mt-8 max-w-[520px] text-[17px] text-mute-2">
        {shared
          ? 'Share with one institution and only that institution sees your name, photo and documents. Take it back from Settings → Who can see me.'
          : 'Institutions are matched to your grades, English and goals, but not to you. No name, no photo and no documents until you say yes.'}
      </p>
    </Reveal>
  );
}

function DocumentsCard() {
  const items = [
    [GraduationCap, 'Transcripts & certificates'],
    [Languages, 'IELTS, TOEFL, Duolingo & PTE'],
    [IdCard, 'Passport, CV & personal statement'],
  ];
  return (
    <Reveal delay={90} className="relative overflow-hidden rounded-[28px] bg-black p-8 text-white md:p-10 lg:col-span-5">
      <div
        aria-hidden="true"
        className="absolute -right-24 -bottom-24 h-80 w-80 rounded-full opacity-60 blur-3xl"
        style={{ background: 'radial-gradient(closest-side, #1f6bff, transparent)' }}
      />
      <p className="eyebrow relative">Documents</p>
      <h3 className="headline relative mt-1.5 text-[clamp(1.9rem,3vw,2.6rem)]">
        Upload once.
        <br />
        Use everywhere.
      </h3>
      <p className="relative mt-5 max-w-[420px] text-[17px] leading-relaxed text-white/60">
        Your results, English test and identity pages live in your passport and go wherever you
        share it. WAEC, GPA, IB or A-Levels: we speak them all.
      </p>
      <ul className="relative mt-16 space-y-4">
        {items.map(([Icon, label]) => (
          <li key={label} className="flex items-center gap-4 text-[17px]">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-white/10">
              <Icon size={18} className="text-brand-hover" />
            </span>
            {label}
          </li>
        ))}
      </ul>
    </Reveal>
  );
}

export default function Students() {
  return (
    <section id="students" data-nav="light" className="bg-cloud py-28 md:py-40" aria-labelledby="students-title">
      <div className="container-x">
        <Reveal as="p" className="eyebrow">For students</Reveal>
        <Reveal delay={60}>
          <h2 id="students-title" className="display mt-4 text-[clamp(2.75rem,6.2vw,5rem)] text-text">
            Three ways in.
            <br />
            One passport.
          </h2>
        </Reveal>
        <Reveal delay={120}>
          <p className="lede mt-6 max-w-[640px] text-mute-2">
            Search on your own, let institutions come to you, or walk the fair floor. Whichever you
            choose, you only fill in your details once.
          </p>
        </Reveal>

        <div className="mt-16 grid gap-5 md:mt-20 lg:grid-cols-3">
          {WAYS.map((w, i) => (
            <WayCard key={w.name} way={w} i={i} />
          ))}
        </div>

        <div className="mt-5 grid gap-5 lg:grid-cols-12">
          <PrivacyCard />
          <DocumentsCard />
        </div>

        <Reveal className="mt-16 flex flex-col items-start gap-5 md:flex-row md:items-center md:gap-8">
          <p className="text-[15px] font-semibold text-mute-2">Who you'll meet</p>
          <ul className="flex flex-wrap gap-2.5">
            {['Universities', 'Colleges & polytechnics', 'Embassies & high commissions', 'Education agencies', 'Scholarships'].map((c) => (
              <li key={c} className="rounded-full bg-white px-4 py-2 text-[15px] text-text ring-1 ring-black/5">
                {c}
              </li>
            ))}
          </ul>
        </Reveal>
      </div>
    </section>
  );
}
