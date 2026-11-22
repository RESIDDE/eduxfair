import { SITE } from '../lib/site';

const Apple = () => (
  <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true">
    <path d="M16.37 12.75c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.47.83-.72 0-1.82-.81-2.99-.79-1.54.02-2.96.9-3.75 2.27-1.6 2.78-.41 6.89 1.15 9.14.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.77.74 2.98.72 1.23-.02 2.01-1.12 2.76-2.23.87-1.28 1.23-2.52 1.25-2.58-.03-.01-2.39-.92-2.4-3.66ZM14.1 5.98c.63-.77 1.06-1.83.94-2.89-.91.04-2.01.61-2.66 1.37-.58.67-1.1 1.76-.96 2.8 1.01.08 2.05-.52 2.68-1.28Z" />
  </svg>
);

const Play = () => (
  <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
    <path fill="#00d7fe" d="M3.6 2.3c-.3.3-.4.7-.4 1.3v16.8c0 .6.1 1 .4 1.3l9.3-9.7-9.3-9.7Z" />
    <path fill="#ffce00" d="m16 15.1-3.1-3.1L16 8.9l3.7 2.1c1 .6 1 1.5 0 2.1L16 15.1Z" />
    <path fill="#ff3a44" d="M16 15.1 12.9 12l-9.3 9.7c.3.4.9.4 1.6 0L16 15.1" />
    <path fill="#00f076" d="M16 8.9 5.2 2.4c-.7-.4-1.3-.3-1.6 0l9.3 9.6L16 8.9Z" />
  </svg>
);

function Badge({ href, icon, small, big, dark }) {
  const live = Boolean(href);
  return (
    <a
      href={live ? href : '#get-app'}
      {...(live ? { target: '_blank', rel: 'noreferrer' } : {})}
      className={`inline-flex h-[50px] items-center gap-2.5 rounded-xl px-4 transition-colors ${
        dark
          ? 'bg-black text-white ring-1 ring-white/25 hover:ring-white/50'
          : 'bg-black text-white hover:bg-ink-3'
      }`}
    >
      {icon}
      <span className="flex flex-col items-start leading-none">
        <span className="text-[11px] tracking-wide text-white/75">{small}</span>
        <span className="mt-0.5 text-[18px] font-semibold tracking-[-0.02em]">{big}</span>
      </span>
    </a>
  );
}

export default function StoreBadges({ dark = true, className = '' }) {
  return (
    <div className={`flex flex-wrap gap-3 ${className}`}>
      <Badge
        dark={dark}
        href={SITE.appStoreUrl}
        icon={<Apple />}
        small={SITE.appStoreUrl ? 'Download on the' : 'Coming soon to'}
        big="App Store"
      />
      <Badge
        dark={dark}
        href={SITE.playStoreUrl}
        icon={<Play />}
        small={SITE.playStoreUrl ? 'Get it on' : 'Coming soon to'}
        big="Google Play"
      />
    </div>
  );
}
