import Reveal from '../components/Reveal';
import WordReveal from '../components/WordReveal';
import { useScrollProgress } from '../lib/hooks';

const ITEMS = [
  ['In-person fairs', 'Walk the hall, meet admissions teams face to face, and connect at every booth with one tap.'],
  ['Live spaces, all year', 'Admissions hours, scholarship Q&As, country briefings and open days, live in the app.'],
  ['Embassies & agencies', 'Visa guidance from embassies and high commissions, and application help from education agencies.'],
];

export default function Statement() {
  const [lineRef, progress] = useScrollProgress({ start: 0.9, end: 0.2 });
  return (
    <section data-nav="dark" className="relative overflow-hidden bg-black text-white" aria-labelledby="statement-title">
      {/* Backdrop: the logo's blues as light falling across the hall */}
      <div aria-hidden="true" className="absolute inset-0">
        <div
          className="absolute inset-0"
          style={{
            background:
              'radial-gradient(70% 60% at 85% 10%, rgba(31,107,255,.55), transparent 60%), radial-gradient(60% 50% at 0% 60%, rgba(11,47,122,.7), transparent 70%), #020814',
          }}
        />
        <img
          src="/logo.png"
          alt=""
          className="absolute -top-[10%] -right-[12%] w-[70%] max-w-[900px] opacity-[0.06] mix-blend-screen invert"
        />
        <div className="absolute inset-x-0 bottom-0 h-1/3 bg-gradient-to-t from-black to-transparent" />
      </div>

      <div className="relative container-x pt-36 pb-28 md:pt-48 md:pb-40">
        <Reveal>
          <span className="glass-dark inline-flex items-center gap-2 rounded-full px-3.5 py-2 text-[15px]">
            <span className="live-dot" /> All year round
          </span>
        </Reveal>
        <Reveal delay={80}>
          <h2 id="statement-title" className="display mt-6 text-[clamp(3.5rem,11vw,9.5rem)] leading-[0.92]">
            Real fairs.
            <br />
            Real futures.
          </h2>
        </Reveal>

        <div ref={lineRef} className="mt-14 flex items-center gap-4 text-[14px] text-white/60">
          <span>Fair day</span>
          <span className="relative h-px flex-1 bg-white/20">
            <span
              className="absolute inset-y-0 left-0 bg-brand"
              style={{ width: `${progress * 100}%`, transition: 'width .2s linear' }}
            />
            <span
              className="absolute top-1/2 h-2.5 w-2.5 -translate-y-1/2 rounded-full bg-brand shadow-[0_0_0_4px_rgba(31,107,255,.25)]"
              style={{ left: `calc(${progress * 100}% - 5px)`, transition: 'left .2s linear' }}
            />
          </span>
          <span>Offer letter</span>
        </div>

        <WordReveal
          className="headline mt-24 max-w-[900px] text-[clamp(1.75rem,3.6vw,3rem)] md:mt-32"
          parts={[
            ['A fair used to end when the hall closed. Now it is'],
            ['where things start.', true],
            ['The institutions you meet keep talking to you, and the next step is always one tap away.'],
          ]}
        />

        <div className="mt-20 grid gap-10 md:mt-28 md:grid-cols-3 md:gap-8">
          {ITEMS.map(([title, body], i) => (
            <Reveal key={title} delay={i * 90} className="border-t border-white/15 pt-6">
              <span className="text-[14px] text-brand-hover">0{i + 1}</span>
              <p className="mt-3 text-[21px] font-semibold tracking-[-0.02em]">{title}</p>
              <p className="mt-2 text-[16px] leading-relaxed text-white/55">{body}</p>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
