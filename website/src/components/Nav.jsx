import { useEffect, useState } from 'react';
import { Menu, X } from 'lucide-react';
import Logo from './Logo';
import { NAV } from '../lib/site';

/**
 * The floating capsule. It reads the `data-nav` of whatever section is
 * underneath it and switches between dark and light glass, so it never sits
 * as a black pill on a white page or the other way round.
 */
export default function Nav({ links = NAV }) {
  const [tone, setTone] = useState('dark');
  const [open, setOpen] = useState(false);

  useEffect(() => {
    let frame = 0;
    const probe = () => {
      frame = 0;
      const y = 40;
      const sections = document.querySelectorAll('[data-nav]');
      for (const s of sections) {
        const r = s.getBoundingClientRect();
        if (r.top <= y && r.bottom > y) {
          setTone(s.dataset.nav);
          return;
        }
      }
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(probe);
    };
    probe();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
    };
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const dark = tone === 'dark' || open;

  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-[60] focus:rounded-full focus:bg-brand focus:px-4 focus:py-2 focus:text-white"
      >
        Skip to content
      </a>
      <header className="pointer-events-none fixed inset-x-0 top-3 z-50 px-3">
        <div className="pointer-events-auto relative mx-auto max-w-[980px] md:w-fit">
          <div
            className={`absolute inset-0 rounded-[28px] transition-opacity duration-500 glass-dark ${dark ? 'opacity-100' : 'opacity-0'}`}
          />
          <div
            className={`absolute inset-0 rounded-[28px] transition-opacity duration-500 glass-light ${dark ? 'opacity-0' : 'opacity-100'}`}
          />
          <nav
            aria-label="Main"
            className="relative flex h-14 items-center gap-2 pr-2 pl-4 md:gap-6 md:pl-5"
          >
            <a href="/" aria-label="EduXFair home" className="mr-auto md:mr-4">
              <Logo dark={dark} />
            </a>
            <ul className="hidden items-center gap-7 md:flex">
              {links.map((l) => (
                <li key={l.href}>
                  <a
                    href={l.href}
                    className={`text-[13.5px] tracking-[-0.005em] transition-colors ${
                      dark ? 'text-white/75 hover:text-white' : 'text-text/75 hover:text-text'
                    }`}
                  >
                    {l.label}
                  </a>
                </li>
              ))}
            </ul>
            <a href="/#get-app" className="btn btn-brand ml-2 h-10 px-4 text-[13.5px] font-semibold">
              Get the app
            </a>
            <button
              type="button"
              className={`grid h-10 w-10 place-items-center rounded-full md:hidden ${dark ? 'text-white' : 'text-text'}`}
              aria-label={open ? 'Close menu' : 'Open menu'}
              aria-expanded={open}
              onClick={() => setOpen((o) => !o)}
            >
              {open ? <X size={20} /> : <Menu size={20} />}
            </button>
          </nav>
          {open && (
            <ul className="relative flex flex-col px-3 pt-1 pb-4 md:hidden">
              {links.map((l) => (
                <li key={l.href}>
                  <a
                    href={l.href}
                    onClick={() => setOpen(false)}
                    className="block rounded-2xl px-3 py-3 text-[17px] font-medium tracking-[-0.01em] text-white/90 active:bg-white/10"
                  >
                    {l.label}
                  </a>
                </li>
              ))}
            </ul>
          )}
        </div>
      </header>
    </>
  );
}
