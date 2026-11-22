/** The EduXFair mark on its white app-icon tile, with an optional wordmark. */
export function LogoTile({ size = 28, className = '' }) {
  return (
    <span
      className={`relative inline-block shrink-0 overflow-hidden bg-white ${className}`}
      style={{ width: size, height: size, borderRadius: size * 0.26 }}
    >
      {/* The source art has wide white margins; scale it up so the mark fills the tile. */}
      <img
        src="/logo.png"
        alt=""
        width={size}
        height={size}
        className="absolute top-1/2 left-1/2"
        style={{
          width: size * 1.5,
          height: size * 1.5,
          maxWidth: 'none',
          transform: 'translate(-50%, -48%)',
        }}
        draggable="false"
      />
    </span>
  );
}

export default function Logo({ size = 28, dark = true, className = '' }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <LogoTile size={size} />
      <span
        className={`text-[17px] font-semibold tracking-[-0.02em] ${dark ? 'text-white' : 'text-text'}`}
      >
        Edu<span className="text-brand">X</span>Fair
      </span>
    </span>
  );
}
