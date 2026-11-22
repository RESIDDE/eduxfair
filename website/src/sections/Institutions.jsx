import { BadgeCheck, CalendarClock, Columns3, Radio, Users } from 'lucide-react';
import Reveal from '../components/Reveal';
import Phone from '../components/Phone';
import { OrgDashboardScreen } from '../components/screens';
import { SITE } from '../lib/site';

const FEATURES = [
  [Users, 'Students who fit', 'See students who meet your entry requirements, without names, and invite them to share.'],
  [Columns3, 'Admissions pipeline', 'Move applicants from submitted to enrolled on one board, with documents attached.'],
  [CalendarClock, 'Inbox & appointments', 'Message students and book one-to-ones across your whole team.'],
  [Radio, 'Spaces & posts', 'Host admissions hours and open days, and post to everyone who follows you.'],
];

export default function Institutions() {
  return (
    <section id="institutions" data-nav="light" className="bg-white py-28 md:py-40" aria-labelledby="inst-title">
      <div className="container-x">
        <div className="grid gap-8 md:grid-cols-2 md:items-end">
          <div>
            <Reveal as="p" className="eyebrow">For institutions</Reveal>
            <Reveal delay={60}>
              <h2 id="inst-title" className="display mt-4 text-[clamp(2.75rem,6.2vw,5rem)] text-text">
                Recruit with
                <br />
                EduXFair.
              </h2>
            </Reveal>
          </div>
          <Reveal delay={120}>
            <p className="lede text-mute-2">
              Meet students who already match your programs, at the fair and all year round.
              Universities, colleges, embassies and agencies sign up in the same app.
            </p>
          </Reveal>
        </div>

        <Reveal className="relative mt-14 overflow-hidden rounded-[28px] md:mt-16">
          <div
            className="relative grid min-h-[560px] items-end md:grid-cols-2 md:items-center"
            style={{ background: 'radial-gradient(90% 90% at 80% 20%, #1f6bff 0%, #0b2f7a 45%, #020814 100%)' }}
          >
            <div
              aria-hidden="true"
              className="absolute inset-0 opacity-[0.12]"
              style={{
                backgroundImage:
                  'linear-gradient(rgba(255,255,255,.5) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.5) 1px, transparent 1px)',
                backgroundSize: '44px 44px',
                maskImage: 'linear-gradient(to left, #000, transparent 70%)',
                WebkitMaskImage: 'linear-gradient(to left, #000, transparent 70%)',
              }}
            />
            <div className="relative order-2 p-8 text-white md:order-1 md:p-12">
              <p className="flex items-center gap-2 text-[15px] font-semibold text-[#9fbaff]">
                <BadgeCheck size={18} /> Verified institution badge
              </p>
              <h3 className="headline mt-4 text-[clamp(2rem,3.6vw,3rem)]">
                Your next intake
                <br />
                is already looking.
              </h3>
              <p className="mt-4 max-w-[420px] text-[17px] leading-relaxed text-white/65">
                Choose <b className="font-semibold text-white">Organisation</b> when you sign up in the
                app. We review every institution before it goes live.
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
                <a href="#get-app" className="btn btn-brand h-[48px] px-5 text-[16px]">
                  Get the app
                </a>
                <a href={`mailto:${SITE.supportEmail}?subject=Exhibiting%20at%20EduXFair`} className="text-[16px] text-white/85 hover:text-white">
                  Exhibit at a fair ›
                </a>
              </div>
            </div>
            <div className="relative order-1 flex justify-center pt-12 md:order-2 md:pt-0">
              <div className="w-[250px] translate-y-10 md:w-[290px] md:translate-y-24">
                <Phone label="Institution dashboard">
                  <OrgDashboardScreen />
                </Phone>
              </div>
            </div>
          </div>
        </Reveal>

        <div className="mt-5 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map(([Icon, title, body], i) => (
            <Reveal key={title} delay={i * 80} className="rounded-[24px] bg-cloud p-7">
              <Icon size={26} className="text-brand" strokeWidth={1.8} />
              <h3 className="mt-10 text-[24px] font-semibold tracking-[-0.025em] text-text">{title}</h3>
              <p className="mt-2 text-[15px] leading-relaxed text-mute-2">{body}</p>
            </Reveal>
          ))}
        </div>

        <Reveal as="p" className="mt-10 text-center text-[17px] text-mute-2">
          Represent several institutions?{' '}
          <a className="link-arrow" href={`mailto:${SITE.partnersEmail}?subject=Agency%20partnership`}>
            Become a partner agency ›
          </a>
        </Reveal>
      </div>
    </section>
  );
}
