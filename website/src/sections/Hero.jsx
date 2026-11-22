import { useEffect, useState } from 'react';
import { BadgeCheck, Check, Sparkles } from 'lucide-react';
import Reveal from '../components/Reveal';
import Phone from '../components/Phone';
import { FeedScreen, MatchesScreen, PassportScreen } from '../components/screens';
import WordReveal from '../components/WordReveal';

function LiveCard() {
  // A little life in the overlay: the "updated" counter ticks.
  const [secs, setSecs] = useState(4);
  useEffect(() => {
    const id = setInterval(() => setSecs((s) => (s >= 59 ? 1 : s + 1)), 1000);
    return () => clearInterval(id);
  }, []);
  return (
    <div className="glass-dark w-[270px] max-w-[calc(100vw-64px)] rounded-[18px] p-3 text-white sm:w-[300px] sm:rounded-[20px] sm:p-4">
      <div className="flex items-center text-[12.5px]">
        <span className="live-dot mr-2" />
        <span className="font-semibold text-brand-hover">New match</span>
        <span className="ml-auto text-white/55">Updated {secs}s ago</span>
      </div>
      <div className="mt-2 text-[16px] font-semibold tracking-[-0.015em]">BSc Computer Science</div>
      <div className="mt-0.5 flex items-center gap-1 text-[13px] text-white/60">
        Maplecrest University <BadgeCheck size={13} className="text-brand-hover" /> · Toronto
      </div>
      <div className="mt-3 flex items-center gap-3">
        <div className="h-[5px] flex-1 overflow-hidden rounded-full bg-white/15">
          <div
            className="h-full origin-left rounded-full bg-brand"
            style={{ width: '94%', animation: 'progress 1.6s var(--ease-out-soft) both 0.6s' }}
          />
        </div>
        <span className="text-[13px] font-semibold">94%</span>
      </div>
    </div>
  );
}

export default function Hero() {
  return (
    <section data-nav="dark" className="relative bg-black pt-36 text-white md:pt-44" aria-labelledby="hero-title">
      <div className="container-x text-center">
        <Reveal as="p" className="eyebrow">
          Education fairs, all year round
        </Reveal>
        <Reveal delay={80}>
          <h1 id="hero-title" className="display mx-auto mt-5 max-w-[11ch] text-[clamp(3.25rem,9.4vw,7.5rem)]">
            One passport. Every fair.
          </h1>
        </Reveal>
        <Reveal delay={160}>
          <p className="lede mx-auto mt-7 max-w-[30ch] text-white/60 md:max-w-[34ch]">
            Build your Education Passport once, let universities that fit you reach out, and
            connect at every booth with one tap. All from one app.
          </p>
        </Reveal>
        <Reveal delay={240} className="mt-9 flex flex-wrap items-center justify-center gap-x-7 gap-y-4">
          <a href="#get-app" className="btn btn-brand h-[50px] px-6 text-[17px]">
            Get the app
          </a>
          <a href="#how" className="link-arrow text-[17px]">
            See how it works ›
          </a>
        </Reveal>
      </div>

      {/* The stage: three real screens over a deep-blue field. */}
      <div className="mt-20 px-3 md:mt-28 md:px-6">
        <Reveal className="relative mx-auto max-w-[1254px]">
          <div
            className="relative h-[560px] overflow-hidden rounded-[28px] md:h-[680px] md:rounded-[36px]"
            style={{
              background:
                'radial-gradient(120% 80% at 50% 0%, #1f6bff 0%, #0b2f7a 42%, #061a47 70%, #020814 100%)',
            }}
          >
            {/* Grid texture */}
            <div
              aria-hidden="true"
              className="absolute inset-0 opacity-[0.14]"
              style={{
                backgroundImage:
                  'linear-gradient(rgba(255,255,255,.5) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.5) 1px, transparent 1px)',
                backgroundSize: '56px 56px',
                maskImage: 'radial-gradient(ellipse at 50% 30%, #000 20%, transparent 75%)',
                WebkitMaskImage: 'radial-gradient(ellipse at 50% 30%, #000 20%, transparent 75%)',
              }}
            />
            {/* Phones */}
            {/* On phones the side handsets shrink and tuck behind the middle one,
                so the fan survives at 390px; from sm up they sit apart as on desktop. */}
            <div className="absolute inset-x-0 top-10 flex items-start justify-center sm:top-14 md:top-16">
              <div className="relative -mr-14 w-[150px] shrink-0 translate-y-12 -rotate-[8deg] opacity-90 sm:mr-0 sm:w-[250px] sm:translate-x-10 sm:translate-y-16">
                <Phone label="EduXFair feed">
                  <FeedScreen />
                </Phone>
              </div>
              <div className="relative z-10 w-[205px] shrink-0 sm:w-[270px] md:w-[300px]">
                <div className="float">
                  <Phone label="Education Passport screen">
                    <PassportScreen />
                  </Phone>
                </div>
              </div>
              <div className="relative -ml-14 w-[150px] shrink-0 translate-y-12 rotate-[8deg] opacity-90 sm:ml-0 sm:w-[250px] sm:-translate-x-10 sm:translate-y-16">
                <Phone label="Matches screen">
                  <MatchesScreen />
                </Phone>
              </div>
            </div>
            {/* Bottom fade */}
            <div
              aria-hidden="true"
              className="absolute inset-x-0 bottom-0 h-48"
              style={{ background: 'linear-gradient(to top, rgba(2,8,20,.95), transparent)' }}
            />
            {/* Floating chips */}
            <div className="absolute inset-x-4 bottom-4 z-20 flex justify-center sm:inset-x-auto sm:bottom-5 sm:left-4 sm:block md:bottom-10 md:left-10">
              <LiveCard />
            </div>
            <div className="glass-dark absolute top-6 right-6 hidden items-center gap-2 rounded-full px-3.5 py-2 text-[13px] text-white lg:flex">
              <span className="grid h-5 w-5 place-items-center rounded-full bg-ok">
                <Check size={12} strokeWidth={3} />
              </span>
              Connected at booth A01
            </div>
            <div className="glass-dark absolute right-10 bottom-10 hidden items-center gap-2 rounded-full px-3.5 py-2 text-[13px] text-white lg:flex">
              <Sparkles size={15} className="text-brand-hover" />
              3 institutions invited you to share
            </div>
          </div>
        </Reveal>
      </div>

      <div className="container-x py-28 md:py-44">
        <WordReveal
          className="headline mx-auto max-w-[920px] text-[clamp(2rem,4.4vw,3.5rem)]"
          parts={[
            ['Choosing where to study used to mean queues at every booth, the same story told twenty times, and a bag of brochures you never read again. Now it takes'],
            ['one passport.', true],
            ['Your grades and documents travel with you,'],
            ['the right universities find you,', true],
            ['and every conversation carries on after the fair ends.'],
          ]}
        />
      </div>
    </section>
  );
}
