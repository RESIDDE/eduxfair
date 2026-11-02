import { Link } from 'react-router-dom';
import {
  BadgeCheck,
  GraduationCap,
  QrCode,
  ShieldCheck,
  Sparkles,
  Workflow,
} from 'lucide-react';
import { Button, SurfaceCard } from '../components/ui';

/**
 * The organisation entrance.
 *
 * Institutions already had separate access — the console is role-gated and a
 * student who lands there is turned away — but they arrived at a bare sign-in
 * form with no explanation of what they were signing in to. This is the page
 * that answers that, and the one that can be linked from an email or a fair.
 */
export default function InstitutionsLanding() {
  return (
    <div className="aurora h-full overflow-auto">
      <div className="max-w-[920px] mx-auto px-6 py-14">
        <header className="flex items-center gap-3">
          <img
            src="/logo.png"
            alt="Eduxfair"
            className="size-11 rounded-tile object-contain bg-white p-0.5 shadow-sm"
          />
          <div>
            <div className="font-bold leading-tight">Eduxfair</div>
            <div className="text-[13px] text-subtle">For institutions and embassies</div>
          </div>
        </header>

        <div className="mt-14 max-w-[640px] animate-enter">
          <h1 className="text-[40px] font-extrabold leading-[1.1] tracking-[-0.5px]">
            Reach students who already match your programs.
          </h1>
          <p className="mt-5 text-[16px] text-muted leading-relaxed">
            Eduxfair runs international education fairs in Lagos. The students
            who attend build a verified Education Passport — their
            qualifications, grades and documents, checked once. Connect shows
            you the ones whose profile fits what you offer, and lets you reach
            them year-round rather than for one afternoon.
          </p>

          <div className="mt-8 flex items-center gap-3 flex-wrap">
            <Link to="/signin?mode=signup">
              <Button size="md">Create an account</Button>
            </Link>
            <Link to="/signin">
              <Button size="md" variant="outline">Sign in</Button>
            </Link>
          </div>

          <p className="mt-4 text-[13px] text-subtle">
            Free to list. You verify your domain, publish your page, and only
            pay when you want student matching and the recruitment pipeline.
          </p>
        </div>

        <div className="mt-16 grid grid-cols-1 md:grid-cols-2 gap-4">
          <Feature
            icon={Sparkles}
            title="Students come to you"
            body="See how many students are currently looking for what you teach,
                  broken down by where they are and what they want to study. Invite
                  the ones who fit — before they have applied anywhere."
          />
          <Feature
            icon={ShieldCheck}
            title="Anonymous until they choose"
            body="You see country, level, field, grade band and intake. You do not
                  see a name, a photo or a document until that student decides to
                  share their passport with you. Most of them are teenagers; this
                  is not negotiable, and it is why they trust the platform."
          />
          <Feature
            icon={BadgeCheck}
            title="A page that answers the real questions"
            body="Cost of living, entry requirements by the student's own country,
                  when applications close, what funding exists. A student from Lagos
                  sees what they need, not a generic prospectus."
          />
          <Feature
            icon={Workflow}
            title="From first contact to enrolled"
            body="Messaging, bookable meetings, and an admission pipeline with an
                  audit trail nobody can edit after the fact — including us."
          />
          <Feature
            icon={QrCode}
            title="Your booth, connected"
            body="At an Eduxfair fair, scan a student's pass and their profile is
                  already in your pipeline. No business cards, no re-typing, and the
                  conversation continues after the hall empties."
          />
          <Feature
            icon={GraduationCap}
            title="Embassies too"
            body="Visa uncertainty derails more admitted students than anything else.
                  Embassies publish real requirements and host sessions, on the same
                  platform the students are already using."
          />
        </div>

        <SurfaceCard className="mt-12 p-7">
          <h2 className="font-bold text-[17px]">How verification works</h2>
          <p className="mt-3 text-[13.5px] text-muted leading-relaxed max-w-prose">
            We email a code to an address on your institution's own domain.
            Confirming it earns the <strong>Verified institution</strong> badge,
            which means exactly that — someone controlling an address on your
            domain vouched for the listing. It is not a claim about
            accreditation, and we say so to students wherever the badge appears.
          </p>
        </SurfaceCard>

        <footer className="mt-14 pb-6 flex items-center justify-between gap-4 flex-wrap text-[13px] text-subtle">
          <span>Students use the Eduxfair app, not this console.</span>
          <Link to="/signin" className="text-accent hover:brightness-110 font-semibold">
            Sign in →
          </Link>
        </footer>
      </div>
    </div>
  );
}

function Feature({ icon: Icon, title, body }) {
  return (
    <SurfaceCard className="p-6">
      <div className="size-10 rounded-tile bg-accent/12 grid place-items-center">
        <Icon size={19} className="text-accent" strokeWidth={2.1} />
      </div>
      <h3 className="mt-4 font-semibold text-[15px]">{title}</h3>
      <p className="mt-2 text-[13.5px] text-muted leading-relaxed">{body}</p>
    </SurfaceCard>
  );
}
