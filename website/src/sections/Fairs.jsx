import { useEffect, useState } from 'react';
import { Check } from 'lucide-react';
import Reveal from '../components/Reveal';
import { useInView } from '../lib/hooks';

// ── The hall ─────────────────────────────────────────────────────────────
const COLS = 6;
const ROWS = ['A', 'B', 'C'];
const BW = 80;
const BH = 52;
const X0 = 95;
const GAP = 18;
const ROW_Y = [100, 220, 340];
const colX = (i) => X0 + i * (BW + GAP);

const STOPS = [
  { code: 'C04', name: 'Visa & immigration desk', short: 'Visa desk', time: '11:06', note: 'Study-permit guidance for Canada and the UK' },
  { code: 'B01', name: 'Lakeshore State University', short: 'Lakeshore', time: '11:24', note: 'Merit scholarships for international students' },
  { code: 'A01', name: 'Maplecrest University', short: 'Maplecrest', time: '11:41', note: 'BSc Computer Science · 94% match' },
  { code: 'A02', name: 'Northgate College London', short: 'Northgate', time: '12:05', note: 'January and September intakes' },
];

// Route from the entrance through each stop, along the aisles.
const PATH = 'M380 505 L380 420 L429 420 L70 420 L70 306 L135 306 L70 306 L70 186 L135 186 L233 186';

function boothRect(code) {
  const row = ROWS.indexOf(code[0]);
  const col = Number(code.slice(1)) - 1;
  return { x: colX(col), y: ROW_Y[row] };
}

function FloorPlan({ selected, onSelect, drawn }) {
  return (
    <svg viewBox="0 0 760 540" className="h-auto w-full" role="img" aria-label="Floor plan of the fair hall with your route between booths">
      <defs>
        <linearGradient id="route" x1="0" x2="1">
          <stop offset="0" stopColor="#1f6bff" stopOpacity=".35" />
          <stop offset="1" stopColor="#3b7dff" />
        </linearGradient>
        <radialGradient id="pulse">
          <stop offset="0" stopColor="#1f6bff" stopOpacity=".55" />
          <stop offset="1" stopColor="#1f6bff" stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* Hall */}
      <rect x="40" y="56" width="680" height="450" rx="22" fill="#141416" stroke="#2c2c30" />
      <text x="62" y="86" fill="#8e8e93" fontSize="13" fontFamily="inherit">Main hall · 18 booths</text>
      {/* Entrance */}
      <rect x="340" y="500" width="80" height="12" rx="6" fill="#000" />
      <text x="380" y="530" fill="#8e8e93" fontSize="12" textAnchor="middle" fontFamily="inherit">Entrance</text>

      {/* Stage */}
      <rect x="95" y="446" width="216" height="40" rx="10" fill="#1b2a4f" stroke="#1f6bff" strokeOpacity=".35" />
      <text x="203" y="471" fill="#9fbaff" fontSize="12.5" textAnchor="middle" fontFamily="inherit">Main stage · Talks</text>
      <rect x="449" y="446" width="216" height="40" rx="10" fill="#1c1c1f" stroke="#2c2c30" />
      <text x="557" y="471" fill="#8e8e93" fontSize="12.5" textAnchor="middle" fontFamily="inherit">Registration</text>

      {/* Booths */}
      {ROWS.map((r, ri) =>
        Array.from({ length: COLS }, (_, ci) => {
          const code = `${r}0${ci + 1}`;
          const stop = STOPS.find((s) => s.code === code);
          const isSel = selected === code;
          return (
            <g
              key={code}
              onClick={stop ? () => onSelect(code) : undefined}
              style={{ cursor: stop ? 'pointer' : 'default' }}
            >
              {isSel && <circle cx={colX(ci) + BW / 2} cy={ROW_Y[ri] + BH / 2} r="58" fill="url(#pulse)" />}
              <rect
                x={colX(ci)}
                y={ROW_Y[ri]}
                width={BW}
                height={BH}
                rx="10"
                fill={isSel ? '#1f6bff' : stop ? '#1f2a44' : '#1f1f22'}
                stroke={isSel ? '#7aa6ff' : stop ? '#1f6bff' : '#2c2c30'}
                strokeOpacity={stop && !isSel ? 0.5 : 1}
                style={{ transition: 'fill .4s, stroke .4s' }}
              />
              <text
                x={colX(ci) + 10}
                y={ROW_Y[ri] + 20}
                fontSize="11"
                fontFamily="inherit"
                fill={isSel ? '#fff' : stop ? '#9fbaff' : '#5b5b60'}
              >
                {code}
              </text>
              {stop && (
                <text x={colX(ci) + 10} y={ROW_Y[ri] + 39} fontSize="12" fontWeight="600" fontFamily="inherit" fill={isSel ? '#fff' : '#e5e5ea'}>
                  {stop.short}
                </text>
              )}
            </g>
          );
        }),
      )}

      {/* Route */}
      <path
        d={PATH}
        fill="none"
        stroke="url(#route)"
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
        pathLength="1"
        strokeDasharray="1"
        strokeDashoffset={drawn ? 0 : 1}
        style={{ transition: 'stroke-dashoffset 2.6s cubic-bezier(.22,1,.36,1)' }}
      />
      <path d={PATH} fill="none" stroke="#fff" strokeOpacity=".35" strokeWidth="1.2" strokeDasharray="4 8" className="dash-flow" />
      {/* You are here */}
      <circle cx="233" cy="186" r="11" fill="#1f6bff" fillOpacity=".25" />
      <circle cx="233" cy="186" r="6" fill="#fff" stroke="#1f6bff" strokeWidth="3" />
    </svg>
  );
}

function Stat({ big, text, i }) {
  return (
    <Reveal delay={i * 90} className="border-t border-white/15 pt-7">
      <div className="text-[52px] leading-none font-semibold tracking-[-0.045em] text-white md:text-[60px]">{big}</div>
      <p className="mt-4 max-w-[290px] text-[17px] text-white/55">{text}</p>
    </Reveal>
  );
}

export default function Fairs() {
  const [selected, setSelected] = useState('A02');
  const [mapRef, inView] = useInView({ threshold: 0.3 });
  const [drawn, setDrawn] = useState(false);
  useEffect(() => {
    if (inView) setDrawn(true);
  }, [inView]);

  const current = STOPS.find((s) => s.code === selected);
  const timeline = [
    { label: 'Checked in at the door', time: '10:58', done: true },
    ...STOPS.map((s, i) => ({
      label: s.name,
      time: s.time,
      code: s.code,
      done: i < STOPS.length - 1,
      now: i === STOPS.length - 1,
    })),
    { label: 'Scholarship Q&A · Main stage', time: '2:00 PM' },
    { label: 'Your fair report', time: 'Tonight' },
  ];

  return (
    <section id="fairs" data-nav="dark" className="bg-black py-28 text-white md:py-40" aria-labelledby="fairs-title">
      <div className="container-x">
        <Reveal as="p" className="eyebrow">Fair day</Reveal>
        <Reveal delay={60}>
          <h2 id="fairs-title" className="display mt-4 text-[clamp(2.75rem,6.2vw,5rem)]">
            Every booth, one tap.
            <br />
            <span className="text-white/55">Every conversation, kept.</span>
          </h2>
        </Reveal>
        <Reveal delay={120}>
          <p className="lede mt-6 max-w-[660px] text-white/55">
            At an EduXFair, your Fair Passport QR is all you carry. Tap at a booth and that
            institution gets your passport, with your permission. When you get home, everything you
            saw is waiting.
          </p>
        </Reveal>

        <Reveal className="mt-16 overflow-hidden rounded-[28px] border border-white/10 bg-ink-2 md:mt-20">
          <div className="grid lg:grid-cols-[1fr_380px]">
            <div ref={mapRef} className="p-4 md:p-8">
              <FloorPlan selected={selected} onSelect={setSelected} drawn={drawn} />
            </div>
            <div className="flex flex-col border-t border-white/10 p-7 md:p-8 lg:border-t-0 lg:border-l">
              <div className="flex items-center gap-2 text-[14px] font-semibold text-brand-hover">
                <span className="live-dot" /> Live fair
              </div>
              <h3 className="mt-3 text-[26px] font-semibold tracking-[-0.025em]">Lagos Education Fair</h3>
              <p className="mt-1 text-[15px] text-white/50">Your visit · 4 booths so far</p>

              <div className="mt-6 rounded-2xl bg-white/[0.06] p-4">
                <div className="text-[12px] font-medium tracking-wide text-white/45 uppercase">Booth {current.code}</div>
                <div className="mt-1 text-[18px] font-semibold tracking-[-0.02em]">{current.name}</div>
                <div className="mt-1 text-[14px] text-white/55">{current.note}</div>
              </div>

              <ol className="mt-6 space-y-3.5">
                {timeline.map((t) => {
                  const isSel = t.code === selected;
                  return (
                    <li key={t.label} className="flex items-center gap-3 text-[15px]">
                      {t.done ? (
                        <span className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full bg-brand">
                          <Check size={13} strokeWidth={3} />
                        </span>
                      ) : t.now ? (
                        <span className="h-[22px] w-[22px] shrink-0 rounded-full border-2 border-brand bg-brand/20" />
                      ) : (
                        <span className="h-[22px] w-[22px] shrink-0 rounded-full bg-white/10" />
                      )}
                      <span className={`min-w-0 truncate ${t.done || t.now ? 'text-white' : 'text-white/40'} ${isSel ? 'font-semibold' : ''}`}>
                        {t.label}
                      </span>
                      <span className={`ml-auto shrink-0 text-[13px] ${t.now ? 'text-brand-hover' : 'text-white/40'}`}>
                        {t.now ? 'Now' : t.time}
                      </span>
                    </li>
                  );
                })}
              </ol>

              <div className="mt-8 border-t border-white/10 pt-6 lg:mt-auto">
                <div className="flex flex-wrap gap-2">
                  {STOPS.map((s) => (
                    <button
                      key={s.code}
                      type="button"
                      onClick={() => setSelected(s.code)}
                      aria-pressed={selected === s.code}
                      className={`rounded-full px-3.5 py-2 text-[13.5px] transition-colors ${
                        selected === s.code
                          ? 'bg-brand text-white'
                          : 'text-white/80 ring-1 ring-white/20 hover:ring-white/40'
                      }`}
                    >
                      {s.code} · {s.short}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </Reveal>

        <div className="mt-20 grid gap-10 md:grid-cols-3 md:gap-8">
          <Stat i={0} big="1 QR" text="Your whole passport, at any booth in the hall." />
          <Stat i={1} big="0 forms" text="To fill in again at the next booth, or the one after that." />
          <Stat i={2} big="Live" text="Admissions hours, Q&As and open days long after the fair." />
        </div>
      </div>
    </section>
  );
}
