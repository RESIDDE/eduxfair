import { useEffect, useRef, useState } from 'react';

// Every screen is laid out on a fixed 300 × 650 canvas and scaled to fit, so
// the mock UI keeps its exact proportions at any size.
export const SCREEN_W = 300;
export const SCREEN_H = 650;

function Battery({ dark }) {
  const c = dark ? '#fff' : '#000';
  return (
    <svg width="22" height="11" viewBox="0 0 22 11" aria-hidden="true">
      <rect x="0.5" y="0.5" width="18" height="10" rx="3" fill="none" stroke={c} strokeOpacity=".4" />
      <rect x="2" y="2" width="14" height="7" rx="1.6" fill={c} />
      <rect x="19.7" y="3.6" width="1.6" height="3.8" rx=".8" fill={c} fillOpacity=".45" />
    </svg>
  );
}

function Signal({ dark }) {
  const c = dark ? '#fff' : '#000';
  return (
    <svg width="16" height="10" viewBox="0 0 16 10" aria-hidden="true">
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={i * 4} y={7 - i * 2.2} width="3" height={3 + i * 2.2} rx=".8" fill={c} />
      ))}
    </svg>
  );
}

export function StatusBar({ dark = false }) {
  return (
    <div
      className={`flex h-[44px] items-end justify-between px-[26px] pb-[6px] text-[13px] font-semibold ${dark ? 'text-white' : 'text-black'}`}
    >
      <span className="tracking-[-0.01em]">9:41</span>
      <span className="flex items-center gap-[5px]">
        <Signal dark={dark} />
        <Battery dark={dark} />
      </span>
    </div>
  );
}

/**
 * An iPhone-style frame. Pass a screen component as children; it is drawn on
 * the 300 × 650 canvas and scaled to the frame's rendered width.
 */
export default function Phone({ children, className = '', dark = false, glow = false, label }) {
  const outer = useRef(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const el = outer.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      // Bezel is 3.6% of the width on each side.
      const inner = entry.contentRect.width * (1 - 0.072);
      setScale(inner / SCREEN_W);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div
      ref={outer}
      role={label ? 'img' : undefined}
      aria-label={label}
      className={`relative aspect-[300/650] w-full ${className}`}
      style={{ maxWidth: 'inherit' }}
    >
      {glow && (
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -inset-[30%] -z-10 rounded-full opacity-70 blur-3xl"
          style={{ background: 'radial-gradient(closest-side, rgba(31,107,255,0.35), transparent)' }}
        />
      )}
      <div
        className="absolute inset-0 rounded-[15%/7%] bg-[#0c0c0d] p-[3.6%]"
        style={{
          boxShadow:
            'inset 0 0 0 1.5px #3a3a3c, 0 0 0 1px rgba(0,0,0,.6), 0 40px 80px -20px rgba(0,0,0,.45), 0 20px 40px -20px rgba(0,0,0,.35)',
        }}
      >
        <div
          className={`relative h-full w-full overflow-hidden rounded-[12%/5.6%] ${dark ? 'bg-black' : 'bg-white'}`}
        >
          <div
            aria-hidden="true"
            className="absolute top-0 left-0 origin-top-left select-none"
            style={{ width: SCREEN_W, height: SCREEN_H, transform: `scale(${scale})` }}
          >
            {children}
          </div>
          {/* Dynamic island */}
          <div
            aria-hidden="true"
            className="absolute top-[1.6%] left-1/2 h-[3.6%] w-[30%] -translate-x-1/2 rounded-full bg-black"
          />
        </div>
      </div>
    </div>
  );
}
