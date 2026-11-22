import Logo from './Logo';
import { SITE } from '../lib/site';

const COLUMNS = [
  [
    'Students',
    [
      ['Education Passport', '/#students'],
      ['Matching', '/#how'],
      ['Fair Passport', '/#fairs'],
      ['Safety & privacy', '/#safety'],
    ],
  ],
  [
    'Institutions',
    [
      ['Recruit with us', '/#institutions'],
      ['Exhibit at a fair', `mailto:${SITE.supportEmail}?subject=Exhibiting%20at%20EduXFair`],
      ['Partner agencies', `mailto:${SITE.partnersEmail}?subject=Agency%20partnership`],
      ['Get the app', '/#get-app'],
    ],
  ],
  [
    'Support',
    [
      ['FAQ', '/#faq'],
      ['Contact support', `mailto:${SITE.supportEmail}`],
      ['Terms of service', '/terms/'],
      ['Privacy policy', '/privacy/'],
      ['Community guidelines', '/guidelines/'],
      ['Delete your account', '/delete-account/'],
    ],
  ],
];

export default function Footer({ children }) {
  return (
    <footer data-nav="light" className="bg-cloud pt-16 pb-10 md:pt-20">
      {children}
      <div className={`container-x ${children ? 'mt-16' : ''}`}>
        <div className="grid gap-12 md:grid-cols-[1.6fr_1fr_1fr_1fr]">
          <div>
            <Logo dark={false} />
            <p className="mt-4 max-w-[300px] text-[14px] leading-relaxed text-mute-2">
              {SITE.tagline} The student recruitment network that starts at the fair and keeps going.
            </p>
          </div>
          {COLUMNS.map(([title, links]) => (
            <nav key={title} aria-label={title}>
              <p className="text-[13px] font-semibold text-text">{title}</p>
              <ul className="mt-4 space-y-3">
                {links.map(([label, href]) => (
                  <li key={label}>
                    <a href={href} className="text-[13px] text-mute-2 transition-colors hover:text-text">
                      {label}
                    </a>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <div className="mt-14 flex flex-col gap-2 border-t border-line pt-6 text-[12px] text-mute md:flex-row md:justify-between">
          <p>Copyright © {new Date().getFullYear()} EduXFair. All rights reserved.</p>
          <p>Operated by {SITE.operator}. App screens show sample data.</p>
        </div>
      </div>
    </footer>
  );
}
