import { useId, type SVGProps } from 'react';

// Geometrie der Marke „p-Kopf“ (Quelle: brand/mark.svg, 1024er-Raster)
const BOWL = 'M256 450a214 214 0 1 0 428 0a214 214 0 1 0 -428 0Z';
const STEM = 'M334 450A78 78 0 0 1 412 528V764A78 78 0 0 1 334 842A78 78 0 0 1 256 764V528A78 78 0 0 1 334 450Z';
const BEAK = 'M529.21 538.93A150 150 0 1 1 729.96 576.91A110 110 0 0 0 529.21 538.93Z';

export interface PaplyMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children'> {
  /** Kantenlänge in px (quadratisch). Standard 24. */
  size?: number | string;
  /** `color`: Grün + Schnabel-Gelb. `mono`: einfarbig in `currentColor` (Schnabel per Fuge abgesetzt). */
  variant?: 'color' | 'mono';
  /** Zugänglicher Name; ohne Titel ist das Zeichen dekorativ (aria-hidden). */
  title?: string;
}

/** Das paply-Zeichen: ein kleines „p“, dessen Bauch der Papageienkopf ist. */
export function PaplyMark({ size = 24, variant = 'color', title, ...rest }: PaplyMarkProps) {
  const id = 'pm' + useId().replace(/[^a-zA-Z0-9_-]/g, '');
  const mono = variant === 'mono';
  const body = mono ? 'currentColor' : `url(#${id}-body)`;
  const beak = mono ? 'currentColor' : `url(#${id}-beak)`;

  return (
    <svg
      viewBox="208 220 640 640"
      width={size}
      height={size}
      role={title ? 'img' : undefined}
      aria-hidden={title ? undefined : true}
      {...rest}
    >
      {title ? <title>{title}</title> : null}
      <defs>
        {!mono && (
          <>
            <linearGradient id={`${id}-body`} x1="300" y1="236" x2="470" y2="842" gradientUnits="userSpaceOnUse">
              <stop offset="0" stopColor="#7cf29a" />
              <stop offset="1" stopColor="#22b45f" />
            </linearGradient>
            <linearGradient id={`${id}-beak`} x1="0" y1="0" x2=".5" y2="1">
              <stop offset="0" stopColor="#ffe066" />
              <stop offset="1" stopColor="#ffa51f" />
            </linearGradient>
          </>
        )}
        <mask id={`${id}-gap`} maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
          <rect width="1024" height="1024" fill="#fff" />
          <circle cx="470" cy="450" r={mono ? 238 : 230} fill="#000" />
        </mask>
        <mask id={`${id}-eye`} maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
          <rect width="1024" height="1024" fill="#fff" />
          <circle cx="520" cy="410" r="62" fill="#000" />
        </mask>
      </defs>
      <path d={BEAK} fill={beak} mask={`url(#${id}-gap)`} />
      <g mask={`url(#${id}-eye)`} fill={body}>
        <path d={BOWL} />
        <path d={STEM} />
      </g>
    </svg>
  );
}
