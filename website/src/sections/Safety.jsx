import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AlertTriangle,
  BadgeCheck,
  Ban,
  Bell,
  Check,
  ChevronLeft,
  ChevronRight,
  Flag,
  Pause,
  Play,
  Trash2,
  VolumeX,
} from 'lucide-react';
import Reveal from '../components/Reveal';
import { prefersReducedMotion } from '../lib/hooks';

const Pill = ({ children }) => (
  <span className="glass-dark inline-flex items-center gap-2.5 rounded-full px-4 py-2.5 text-[15px] text-white">
    <span className="grid h-5 w-5 place-items-center rounded-full bg-brand">
      <Check size={12} strokeWidth={3} />
    </span>
    {children}
  </span>
);

const Panel = ({ children, className = '' }) => (
  <div className={`glass-dark w-full max-w-[360px] rounded-[22px] p-4 text-white ${className}`}>{children}</div>
);

const SLIDES = [
  {
    eyebrow: 'Private by default',
    title: 'No one sees your passport until you share it.',
    body: 'Institutions are matched to a profile without your name or photo. You choose who gets the rest.',
    visual: (
      <div className="flex flex-col items-start gap-3">
        <Pill>Name hidden</Pill>
        <Pill>Photo hidden</Pill>
        <Pill>Documents locked</Pill>
      </div>
    ),
  },
  {
    eyebrow: 'Who can see me',
    title: 'Take access back, any time.',
    body: 'Every institution you have shared with, in one list. One tap revokes it.',
    visual: (
      <Panel>
        <div className="px-1 pb-2 text-[13px] text-white/50">Shared with</div>
        {['Maplecrest University', 'Northgate College London', 'Lakeshore State University'].map((n, i) => (
          <div key={n} className={`flex items-center gap-3 px-1 py-2.5 ${i ? 'border-t border-white/10' : ''}`}>
            <span className="h-8 w-8 shrink-0 rounded-full bg-gradient-to-br from-brand to-navy" />
            <span className="min-w-0 truncate text-[14px]">{n}</span>
            <span className="ml-auto shrink-0 rounded-full bg-white/10 px-3 py-1 text-[12.5px] font-medium">Revoke</span>
          </div>
        ))}
      </Panel>
    ),
  },
  {
    eyebrow: 'Verified institutions',
    title: 'Real admissions teams, checked.',
    body: 'Institutions are reviewed before they get a verified badge, so you know who you are talking to.',
    visual: (
      <Panel className="p-5">
        <div className="flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-full bg-gradient-to-br from-[#d62e2e] to-[#7a0f1c] text-[15px] font-bold">MU</span>
          <div>
            <div className="flex items-center gap-1.5 text-[16px] font-semibold">
              Maplecrest University <BadgeCheck size={16} className="text-brand-hover" />
            </div>
            <div className="text-[13px] text-white/55">Toronto, Canada</div>
          </div>
        </div>
        <div className="mt-4 flex items-center gap-2 rounded-xl bg-white/[0.07] px-3 py-2.5 text-[13px]">
          <BadgeCheck size={15} className="text-brand-hover" /> Verified institution
          <span className="ml-auto text-white/45">Reviewed by EduXFair</span>
        </div>
      </Panel>
    ),
  },
  {
    eyebrow: 'Report & block',
    title: 'Abuse does not get a second message.',
    body: 'Report a post, a comment or an account. Block or mute anyone, and review it all in Settings.',
    visual: (
      <Panel className="p-2">
        {[
          [Flag, 'Report post', 'text-[#ff6b6b]'],
          [Flag, 'Report account', 'text-[#ff6b6b]'],
          [Ban, 'Block', 'text-[#ff6b6b]'],
          [VolumeX, 'Mute', 'text-white'],
        ].map(([Icon, label, c], i) => (
          <div key={label} className={`flex items-center gap-3 px-3 py-3 text-[15px] ${c} ${i ? 'border-t border-white/10' : ''}`}>
            <Icon size={17} /> {label}
          </div>
        ))}
      </Panel>
    ),
  },
  {
    eyebrow: 'Filtered before posting',
    title: 'Harmful posts stopped at the door.',
    body: 'Threats and exploitation are refused before they upload. Scam promises like “guaranteed visa” get a warning first.',
    visual: (
      <Panel>
        <div className="rounded-xl bg-white/[0.07] p-3 text-[14px] text-white/85">
          Guaranteed visa in two weeks, no IELTS needed. DM me 💸
        </div>
        <div className="mt-3 flex items-start gap-2.5 rounded-xl bg-[#f59e0b]/15 p-3 text-[13px] text-[#fbbf24]">
          <AlertTriangle size={16} className="mt-0.5 shrink-0" />
          This reads like an admissions promise no one can make. Post anyway?
        </div>
      </Panel>
    ),
  },
  {
    eyebrow: 'Notifications',
    title: 'Always in the loop.',
    body: 'A new match, an invitation, a reply from admissions, a change to your application. You hear about it first.',
    visual: (
      <div className="flex w-full max-w-[360px] flex-col gap-2.5">
        {[
          ['Conditional offer', 'now', 'Maplecrest updated your application.'],
          ['New message', '12m', 'Northgate: “Happy to look at your transcript.”'],
          ['New match', '2h', 'BS Cybersecurity · 81% match'],
        ].map(([t, when, body], i) => (
          <div key={t} className="glass-dark flex gap-3 rounded-[18px] p-3.5 text-white" style={{ opacity: 1 - i * 0.18 }}>
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-[10px] bg-brand">
              <Bell size={16} />
            </span>
            <div className="min-w-0">
              <div className="flex items-center text-[14px] font-semibold">
                {t}
                <span className="ml-2 text-[12px] font-normal text-white/45">{when}</span>
              </div>
              <div className="truncate text-[13px] text-white/60">{body}</div>
            </div>
          </div>
        ))}
      </div>
    ),
  },
  {
    eyebrow: 'Delete any time',
    title: 'Leave, and your data leaves with you.',
    body: 'Delete your account from inside the app. Your passport, documents and posts go with it.',
    visual: (
      <Panel className="p-5">
        <div className="flex items-center gap-3 text-[16px] font-semibold text-[#ff6b6b]">
          <Trash2 size={18} /> Delete account
        </div>
        <div className="mt-3 text-[13px] leading-relaxed text-white/55">
          Your passport, documents, messages and posts are removed. Type DELETE to confirm.
        </div>
        <div className="mt-4 rounded-xl bg-white/[0.07] px-3 py-2.5 font-mono text-[14px] tracking-widest">DELETE</div>
      </Panel>
    ),
  },
];

const TINTS = [
  'linear-gradient(120deg,#020814 0%,#061a47 55%,#0b2f7a 100%)',
  'linear-gradient(120deg,#0b0b0c 0%,#10204a 60%,#1f6bff 140%)',
  'linear-gradient(120deg,#020814 0%,#0b2f7a 70%,#1f6bff 130%)',
  'linear-gradient(120deg,#0b0b0c 0%,#2a0f14 70%,#5a1420 120%)',
  'linear-gradient(120deg,#0b0b0c 0%,#2a1d06 70%,#5c3d06 130%)',
  'linear-gradient(120deg,#020814 0%,#061a47 60%,#1f6bff 130%)',
  'linear-gradient(120deg,#0b0b0c 0%,#1f1f22 100%)',
];

export default function Safety() {
  const track = useRef(null);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(() => !prefersReducedMotion());

  const goTo = useCallback((i) => {
    const el = track.current;
    if (!el) return;
    const n = (i + SLIDES.length) % SLIDES.length;
    const card = el.children[n];
    const pad = parseFloat(getComputedStyle(el).paddingLeft) || 0;
    el.scrollTo({ left: card.offsetLeft - el.offsetLeft - pad, behavior: 'smooth' });
  }, []);

  // Keep `index` in sync with manual swipes.
  useEffect(() => {
    const el = track.current;
    if (!el) return;
    let frame = 0;
    const onScroll = () => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        const w = el.children[0].getBoundingClientRect().width + 20;
        setIndex(Math.round(el.scrollLeft / w));
      });
    };
    el.addEventListener('scroll', onScroll, { passive: true });
    return () => el.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (!playing) return;
    const id = setTimeout(() => goTo(index + 1), 6000);
    return () => clearTimeout(id);
  }, [playing, index, goTo]);

  return (
    <section id="safety" data-nav="light" className="bg-cloud py-28 md:py-40" aria-labelledby="safety-title">
      <div className="container-x">
        <div className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
          <div>
            <Reveal as="p" className="eyebrow">Safety, built in</Reveal>
            <Reveal delay={60}>
              <h2 id="safety-title" className="display mt-4 text-[clamp(2.75rem,6.2vw,5rem)] text-text">
                Your future, your call.
              </h2>
            </Reveal>
          </div>
          <Reveal delay={120}>
            <p className="max-w-[380px] text-[17px] leading-relaxed text-mute-2">
              Privacy controls, verified institutions and people you can reach, on every account from
              day one.
            </p>
          </Reveal>
        </div>
      </div>

      <Reveal className="mt-14">
        <div
          ref={track}
          className="no-scrollbar flex snap-x snap-mandatory scroll-px-4 gap-5 overflow-x-auto px-4 sm:scroll-px-6 sm:px-6 xl:scroll-px-[calc((100vw-1216px)/2)] xl:px-[calc((100vw-1216px)/2)]"
          aria-roledescription="carousel"
          aria-label="Safety features"
        >
          {SLIDES.map((s, i) => (
            <article
              key={s.eyebrow}
              aria-roledescription="slide"
              aria-label={`${i + 1} of ${SLIDES.length}: ${s.eyebrow}`}
              className="relative grid w-[calc(100vw-32px)] max-w-[1216px] shrink-0 snap-start overflow-hidden rounded-[28px] text-white sm:w-[calc(100vw-48px)] md:min-h-[420px] md:grid-cols-2"
              style={{ background: TINTS[i % TINTS.length] }}
            >
              <div
                aria-hidden="true"
                className="absolute inset-0 opacity-[0.07]"
                style={{
                  backgroundImage: 'radial-gradient(circle at 1px 1px, #fff 1px, transparent 0)',
                  backgroundSize: '22px 22px',
                }}
              />
              <div className="relative flex flex-col justify-center p-8 md:p-12">
                <p className="eyebrow text-brand-hover">{s.eyebrow}</p>
                <h3 className="headline mt-3 max-w-[460px] text-[clamp(1.9rem,3.2vw,2.75rem)]">{s.title}</h3>
                <p className="mt-4 max-w-[440px] text-[17px] leading-relaxed text-white/65">{s.body}</p>
              </div>
              <div className="relative flex items-center justify-center p-8 pt-0 md:p-12">{s.visual}</div>
            </article>
          ))}
        </div>
      </Reveal>

      <div className="container-x mt-7 flex items-center">
        <button
          type="button"
          onClick={() => setPlaying((p) => !p)}
          aria-label={playing ? 'Pause slideshow' : 'Play slideshow'}
          className="grid h-11 w-11 place-items-center rounded-full bg-black/[0.07] text-text transition-colors hover:bg-black/10"
        >
          {playing ? <Pause size={16} fill="currentColor" /> : <Play size={16} fill="currentColor" />}
        </button>
        <div className="ml-4 flex items-center gap-1.5">
          {SLIDES.map((s, i) => (
            <button
              key={s.eyebrow}
              type="button"
              onClick={() => goTo(i)}
              aria-label={`Go to slide ${i + 1}`}
              aria-current={index === i}
              className={`h-2 rounded-full transition-all duration-500 ${index === i ? 'w-6 bg-text' : 'w-2 bg-black/20 hover:bg-black/35'}`}
            />
          ))}
        </div>
        <div className="ml-auto flex gap-3">
          <button
            type="button"
            onClick={() => goTo(index - 1)}
            aria-label="Previous slide"
            className="grid h-11 w-11 place-items-center rounded-full bg-black/[0.07] text-text transition-colors hover:bg-black/10"
          >
            <ChevronLeft size={18} />
          </button>
          <button
            type="button"
            onClick={() => goTo(index + 1)}
            aria-label="Next slide"
            className="grid h-11 w-11 place-items-center rounded-full bg-black/[0.07] text-text transition-colors hover:bg-black/10"
          >
            <ChevronRight size={18} />
          </button>
        </div>
      </div>
    </section>
  );
}
