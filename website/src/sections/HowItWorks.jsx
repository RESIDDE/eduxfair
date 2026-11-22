import { useEffect, useRef, useState } from 'react';
import Reveal from '../components/Reveal';
import Phone from '../components/Phone';
import { ApplicationsScreen, MatchesScreen, MeetScreen, PassportScreen } from '../components/screens';

const STEPS = [
  {
    key: 'Build',
    title: 'Build your passport once.',
    body: 'Add your school results, English test and the documents institutions ask for. It takes one sitting, and you never retype it at another booth.',
    Screen: PassportScreen,
  },
  {
    key: 'Match',
    title: 'Let the right ones find you.',
    body: 'We match your passport against every program on EduXFair. Institutions see a profile without your name and invite you to share. You decide.',
    Screen: MatchesScreen,
  },
  {
    key: 'Meet',
    title: 'Talk to admissions, directly.',
    body: 'Message admissions officers, book a one-to-one, or drop into a live admissions hour, scholarship Q&A or open day.',
    Screen: MeetScreen,
  },
  {
    key: 'Apply',
    title: 'Apply and track every step.',
    body: 'Send applications straight from your passport and watch each one move from submitted to offer, all in one list.',
    Screen: ApplicationsScreen,
  },
];

function StepLabel({ n, label, active = true }) {
  return (
    <div className="flex items-center gap-3">
      <span
        className={`grid h-8 w-8 place-items-center rounded-full text-[14px] font-semibold transition-colors duration-500 ${
          active ? 'bg-ink text-white' : 'bg-line text-white'
        }`}
      >
        {n}
      </span>
      <span className="text-[17px] text-mute-2">{label}</span>
    </div>
  );
}

export default function HowItWorks() {
  const [active, setActive] = useState(0);
  const stepRefs = useRef([]);

  // Desktop: the step whose text crosses the middle of the screen drives the
  // sticky phone.
  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) setActive(Number(e.target.dataset.index));
        });
      },
      { rootMargin: '-45% 0px -45% 0px' },
    );
    stepRefs.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, []);

  return (
    <section id="how" data-nav="light" className="overflow-x-clip bg-white py-28 md:py-40" aria-labelledby="how-title">
      <div className="container-x">
        <div className="text-center">
          <Reveal as="p" className="eyebrow">How it works</Reveal>
          <Reveal delay={60}>
            <h2 id="how-title" className="display mx-auto mt-4 max-w-[12ch] text-[clamp(2.75rem,6.2vw,5rem)] text-text">
              From first booth to offer letter.
            </h2>
          </Reveal>
          <Reveal delay={120}>
            <p className="lede mx-auto mt-6 max-w-[560px] text-mute-2">
              Four steps, one app, and every conversation in one place.
            </p>
          </Reveal>
        </div>

        {/* Desktop: text scrolls, phone stays */}
        <div className="mt-24 hidden grid-cols-2 gap-16 lg:grid">
          <div>
            {STEPS.map((s, i) => (
              <div
                key={s.key}
                ref={(el) => (stepRefs.current[i] = el)}
                data-index={i}
                className={`flex min-h-[78vh] flex-col justify-center transition-opacity duration-500 ${
                  active === i ? 'opacity-100' : 'opacity-30'
                }`}
              >
                <StepLabel n={i + 1} label={s.key} active={active === i} />
                <h3 className="headline mt-5 text-[44px] text-text">{s.title}</h3>
                <p className="mt-5 max-w-[460px] text-[22px] leading-[1.45] tracking-[-0.012em] text-mute-2">
                  {s.body}
                </p>
              </div>
            ))}
          </div>
          <div className="relative">
            <div className="sticky top-[calc(50vh-330px)] flex h-[660px] items-center justify-center">
              <div className="relative w-[304px]">
                {/* Sized by the first phone; the rest stack on top. */}
                {STEPS.map(({ key, Screen }, i) => (
                  <div
                    key={key}
                    className={`transition-all duration-700 ease-[var(--ease-out-soft)] ${
                      i === 0 ? 'relative' : 'absolute inset-0'
                    } ${active === i ? 'scale-100 opacity-100' : 'pointer-events-none scale-[0.96] opacity-0'}`}
                    aria-hidden={active !== i}
                  >
                    <Phone glow label={`${key} screen`}>
                      <Screen />
                    </Phone>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Mobile and tablet: each step carries its own phone */}
        <div className="mt-20 space-y-24 lg:hidden">
          {STEPS.map(({ key, title, body, Screen }, i) => (
            <Reveal key={key} className="flex flex-col items-center gap-10 md:flex-row md:items-center md:gap-12">
              <div className="w-full md:flex-1">
                <StepLabel n={i + 1} label={key} />
                <h3 className="headline mt-4 text-[34px] text-text">{title}</h3>
                <p className="mt-4 text-[19px] leading-[1.5] text-mute-2">{body}</p>
              </div>
              <div className="w-[260px] shrink-0">
                <Phone glow label={`${key} screen`}>
                  <Screen />
                </Phone>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
