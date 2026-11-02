import { initials } from '../../lib/format';

/** Initials in a neutral circle. Green is kept for status, so avatars stay grey. */
export function Avatar({
  name, src, fallback, size = 36, glass = false, className = '', ...props
}) {
  return (
    <span
      {...props}
      className={`relative grid place-items-center shrink-0 overflow-hidden rounded-full font-bold ${
        glass ? 'glass text-white' : 'bg-surface-variant text-white/85'
      } ${className}`}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.36) }}
    >
      {src ? (
        <img
          src={src}
          alt=""
          className="size-full object-cover"
          // A broken image is worse than no image: it leaves a torn icon where
          // a face should be, so it falls back to the initials underneath.
          onError={(e) => { e.currentTarget.style.display = 'none'; }}
        />
      ) : null}
      {/* Behind the image, so it shows through if that fails to load. */}
      <span className={src ? 'absolute -z-10' : undefined}>
        {fallback ?? initials(name)}
      </span>
    </span>
  );
}
