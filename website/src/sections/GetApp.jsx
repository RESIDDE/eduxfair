import Reveal from '../components/Reveal';
import Phone from '../components/Phone';
import StoreBadges from '../components/StoreBadges';
import { LogoTile } from '../components/Logo';
import { FairPassportScreen, FeedScreen, MatchesScreen } from '../components/screens';

export default function GetApp() {
  return (
    <section id="get-app" data-nav="dark" className="relative overflow-hidden bg-black pt-32 text-white md:pt-44" aria-labelledby="get-title">
      <div
        aria-hidden="true"
        className="absolute inset-x-0 bottom-0 h-[70%]"
        style={{ background: 'radial-gradient(60% 70% at 50% 100%, rgba(31,107,255,.45), transparent 70%)' }}
      />
      <div className="relative container-x text-center">
        <Reveal className="mx-auto w-fit">
          <div className="relative">
            <div aria-hidden="true" className="absolute -inset-8 rounded-full bg-brand/40 blur-3xl" />
            <LogoTile size={96} className="relative shadow-[0_20px_60px_rgba(31,107,255,.35)]" />
          </div>
        </Reveal>
        <Reveal delay={80}>
          <h2 id="get-title" className="display mx-auto mt-10 max-w-[12ch] text-[clamp(3rem,7.4vw,6rem)]">
            Your next chapter starts here.
          </h2>
        </Reveal>
        <Reveal delay={160}>
          <p className="lede mx-auto mt-6 max-w-[34ch] text-white/60">
            Build your passport, meet institutions and apply from your phone. Free on iPhone and
            Android.
          </p>
        </Reveal>
        <Reveal delay={220}>
          <StoreBadges className="mt-9 justify-center" />
        </Reveal>
      </div>

      <div className="relative mx-auto mt-16 flex h-[380px] max-w-[900px] items-start justify-center overflow-hidden px-4 sm:h-[420px] md:mt-20 md:h-[520px]">
        <Reveal delay={100} className="-mr-14 w-[150px] shrink-0 translate-y-12 -rotate-[9deg] opacity-80 sm:mr-0 sm:w-[260px] sm:translate-x-12 sm:translate-y-16">
          <Phone label="Fair Passport screen">
            <FairPassportScreen />
          </Phone>
        </Reveal>
        <Reveal className="relative z-10 w-[205px] shrink-0 sm:w-[270px] md:w-[300px]">
          <Phone label="Feed screen">
            <FeedScreen />
          </Phone>
        </Reveal>
        <Reveal delay={100} className="-ml-14 w-[150px] shrink-0 translate-y-12 rotate-[9deg] opacity-80 sm:ml-0 sm:w-[260px] sm:-translate-x-12 sm:translate-y-16">
          <Phone label="Matches screen">
            <MatchesScreen />
          </Phone>
        </Reveal>
      </div>
      <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 bottom-0 z-20 h-32 bg-gradient-to-t from-black to-transparent" />
    </section>
  );
}
