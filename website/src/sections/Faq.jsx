import { useState } from 'react';
import { Mail, Plus } from 'lucide-react';
import Reveal from '../components/Reveal';
import { SITE } from '../lib/site';

const QA = [
  [
    'Is EduXFair free for students?',
    'Yes. Building your Education Passport, getting matched, messaging institutions and using your Fair Passport at a fair cost students nothing.',
  ],
  [
    'Who can see my Education Passport?',
    'Nobody, until you share it. Institutions are matched to your grades, English and goals without seeing your name, photo or documents. When you share with one institution, only that institution sees the rest, and you can take it back any time from Settings → Who can see me.',
  ],
  [
    'How does matching work?',
    'We compare your passport (study level, field, grades, English score and budget) with each program’s entry requirements. Programs you fit show up in Matches, and institutions with a match can invite you to share.',
  ],
  [
    'What is a Fair Passport?',
    'A QR code in the app. Show it at a booth and that institution can connect with you on the spot, with no forms to fill in. After the fair you get a report of every booth you met and every program that matched.',
  ],
  [
    'Which qualifications do you understand?',
    'WAEC and NECO, percentages, GPA on a 4.0 or 5.0 scale, UK degree classifications, the IB diploma and A-Level points, plus IELTS, TOEFL iBT, Duolingo English Test, PTE Academic and WAEC English.',
  ],
  [
    'Can I use EduXFair without going to a fair?',
    'Yes. Matching, messaging, appointments and live spaces like admissions hours, scholarship Q&As and open days all work from home, all year round.',
  ],
  [
    'How old do I need to be?',
    'You must be at least 16 to hold an account. If you are under 18, you need your parent or guardian’s permission.',
  ],
  [
    'How do I delete my account?',
    'In the app, go to Settings → Delete account. No longer have the app? Sign in at educationfair.com.ng/delete-account instead. Either way, your passport, documents, messages and posts are removed. The Privacy Policy explains the few records the law requires us to keep.',
  ],
  [
    'How does an institution join?',
    'Download the app and choose Organisation when you sign up: university, college or polytechnic, embassy or high commission, or education agency. We review every institution before it goes live.',
  ],
];

function Item({ q, a, open, onToggle, i }) {
  const id = `faq-${i}`;
  return (
    <div className="border-b border-line">
      <h3>
        <button
          type="button"
          aria-expanded={open}
          aria-controls={id}
          onClick={onToggle}
          className="flex w-full items-center gap-6 py-6 text-left text-[19px] font-semibold tracking-[-0.02em] text-text md:text-[21px]"
        >
          <span className="flex-1">{q}</span>
          <span
            className={`grid h-8 w-8 shrink-0 place-items-center rounded-full bg-cloud transition-transform duration-300 ${open ? 'rotate-45' : ''}`}
          >
            <Plus size={16} />
          </span>
        </button>
      </h3>
      <div
        id={id}
        role="region"
        className="grid transition-[grid-template-rows] duration-400 ease-[var(--ease-out-soft)]"
        style={{ gridTemplateRows: open ? '1fr' : '0fr' }}
      >
        <div className="overflow-hidden">
          <p className="max-w-[620px] pb-7 text-[17px] leading-relaxed text-mute-2">{a}</p>
        </div>
      </div>
    </div>
  );
}

export default function Faq() {
  const [open, setOpen] = useState(0);
  return (
    <section id="faq" data-nav="light" className="bg-white py-28 md:py-40" aria-labelledby="faq-title">
      <div className="container-x grid gap-12 lg:grid-cols-[1fr_1.35fr] lg:gap-16">
        <div>
          <Reveal as="p" className="eyebrow">FAQ</Reveal>
          <Reveal delay={60}>
            <h2 id="faq-title" className="display mt-4 text-[clamp(2.75rem,6.2vw,5rem)] text-text">
              Questions?
              <br />
              Answers.
            </h2>
          </Reveal>
          <Reveal delay={120}>
            <p className="mt-8 text-[21px] tracking-[-0.015em] text-mute-2">
              Can't find what you need?{' '}
              <a className="link-arrow" href={`mailto:${SITE.supportEmail}`}>
                Email our team ›
              </a>
            </p>
          </Reveal>
        </div>
        <Reveal delay={100} className="border-t border-line">
          {QA.map(([q, a], i) => (
            <Item key={q} q={q} a={a} i={i} open={open === i} onToggle={() => setOpen(open === i ? -1 : i)} />
          ))}
        </Reveal>
      </div>
    </section>
  );
}

export function ContactBand() {
  return (
    <div className="container-x">
      <Reveal className="flex flex-col items-start gap-6 rounded-[28px] bg-white p-8 md:flex-row md:items-center md:p-10">
        <div className="flex-1">
          <h2 className="text-[28px] font-semibold tracking-[-0.03em] text-text">Bringing a whole school?</h2>
          <p className="mt-2 max-w-[560px] text-[17px] leading-relaxed text-mute-2">
            Counsellors, schools and education agencies: tell us about your students and we will
            help you get everyone set up before the next fair.
          </p>
        </div>
        <a href={`mailto:${SITE.supportEmail}?subject=Bringing%20our%20students`} className="btn bg-ink-3 h-[50px] px-6 text-[17px] text-white hover:bg-ink-4">
          <Mail size={18} /> Talk to us
        </a>
      </Reveal>
    </div>
  );
}
