import Nav from '../components/Nav';
import Footer from '../components/Footer';
import policies from '../content/policies.json';
import { SITE } from '../lib/site';

const DOCS = [
  ['privacy', 'Privacy Policy', '/privacy/'],
  ['terms', 'Terms of Service', '/terms/'],
  ['guidelines', 'Community Guidelines', '/guidelines/'],
];

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

// Turn the support address into a link wherever the text mentions it.
function linkify(text) {
  const parts = text.split(SITE.supportEmail);
  return parts.flatMap((p, i) =>
    i === 0
      ? [p]
      : [
          <a key={i} className="text-brand underline-offset-4 hover:underline" href={`mailto:${SITE.supportEmail}`}>
            {SITE.supportEmail}
          </a>,
          p,
        ],
  );
}

export default function Legal({ page }) {
  const doc = policies[page];
  return (
    <>
      <Nav />
      <main id="main">
        <header data-nav="dark" className="bg-black pt-36 pb-16 text-white md:pt-44 md:pb-20">
          <div className="container-x max-w-[880px]!">
            <nav aria-label="Policies" className="flex flex-wrap gap-2">
              {DOCS.map(([key, label, href]) => (
                <a
                  key={key}
                  href={href}
                  aria-current={key === page ? 'page' : undefined}
                  className={`rounded-full px-3.5 py-1.5 text-[13.5px] transition-colors ${
                    key === page ? 'bg-white text-black' : 'text-white/70 ring-1 ring-white/20 hover:text-white'
                  }`}
                >
                  {label}
                </a>
              ))}
            </nav>
            <h1 className="display mt-10 text-[clamp(2.75rem,7vw,5rem)]">{doc.title}</h1>
            <p className="lede mt-5 max-w-[34ch] text-white/60">{doc.summary}</p>
            <p className="mt-6 text-[14px] text-white/40">Last updated {doc.lastUpdated}</p>
          </div>
        </header>

        <article data-nav="light" className="bg-white py-16 md:py-24">
          <div className="container-x grid max-w-[1080px]! gap-12 lg:grid-cols-[220px_1fr]">
            <aside className="hidden lg:block">
              <nav aria-label="On this page" className="sticky top-28">
                <p className="text-[13px] font-semibold text-text">On this page</p>
                <ul className="mt-3 space-y-2.5">
                  {doc.sections.map((s) => (
                    <li key={s.heading}>
                      <a href={`#${slug(s.heading)}`} className="text-[13px] leading-snug text-mute-2 hover:text-text">
                        {s.heading}
                      </a>
                    </li>
                  ))}
                </ul>
              </nav>
            </aside>
            <div className="max-w-[680px]">
              {doc.sections.map((s) => (
                <section key={s.heading} id={slug(s.heading)} className="mb-12 scroll-mt-28">
                  <h2 className="text-[26px] font-semibold tracking-[-0.025em] text-text">{s.heading}</h2>
                  {s.body.map((p, i) => (
                    <p key={i} className="mt-4 text-[17px] leading-[1.65] text-[#424245]">
                      {linkify(p)}
                    </p>
                  ))}
                  {s.bullets.length > 0 && (
                    <ul className="mt-4 space-y-3">
                      {s.bullets.map((b, i) => (
                        <li key={i} className="relative pl-6 text-[17px] leading-[1.65] text-[#424245]">
                          <span className="absolute top-[0.72em] left-1 h-1.5 w-1.5 rounded-full bg-brand" />
                          {linkify(b)}
                        </li>
                      ))}
                    </ul>
                  )}
                </section>
              ))}
              <p className="rounded-2xl bg-cloud p-5 text-[15px] leading-relaxed text-mute-2">
                This is the same text that ships inside the EduXFair app. Questions about it? Write to{' '}
                <a className="text-brand hover:underline" href={`mailto:${SITE.supportEmail}`}>
                  {SITE.supportEmail}
                </a>
                .
              </p>
            </div>
          </div>
        </article>
      </main>
      <Footer />
    </>
  );
}
