import { useEffect, useState } from "react";

interface AnimatedLogoProps {
  size?: number;
  className?: string;
}

export function AnimatedLogo({ size = 48, className = "" }: AnimatedLogoProps) {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    // Align the first tick to the next whole second so the key advances in sync
    // with wall-clock seconds rather than drifting at an arbitrary phase.
    let timer: number | undefined;
    const tick = () => {
      setNow(new Date());
      const msUntilNext = 1000 - (Date.now() % 1000);
      timer = window.setTimeout(tick, msUntilNext);
    };
    const msUntilFirst = 1000 - (Date.now() % 1000);
    timer = window.setTimeout(tick, msUntilFirst);
    return () => { if (timer !== undefined) window.clearTimeout(timer); };
  }, []);

  const h = now.getHours() % 12;
  const m = now.getMinutes();
  const s = now.getSeconds();

  const hourAngle = h * 30 + m * 0.5;
  const minuteAngle = m * 6 + s * 0.1;
  // Key shaft is drawn along +x in the group's local frame. At second=0 we want
  // it pointing up (12 o'clock = -y), which is -90°. Each second adds 6°.
  const secondAngle = s * 6 - 90;

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 512 512"
      width={size}
      height={size}
      className={className}
    >
      {/* Clock face */}
      <circle cx="256" cy="256" r="240" fill="#f0ebe5" stroke="#4a3728" strokeWidth="24" />

      {/* Hour tick marks */}
      <g stroke="#4a3728" strokeWidth="8" strokeLinecap="round">
        <line x1="256" y1="40" x2="256" y2="72" />
        <line x1="364" y1="76" x2="348" y2="104" />
        <line x1="436" y1="148" x2="408" y2="164" />
        <line x1="472" y1="256" x2="440" y2="256" />
        <line x1="436" y1="364" x2="408" y2="348" />
        <line x1="364" y1="436" x2="348" y2="408" />
        <line x1="256" y1="472" x2="256" y2="440" />
        <line x1="148" y1="436" x2="164" y2="408" />
        <line x1="76" y1="364" x2="104" y2="348" />
        <line x1="40" y1="256" x2="72" y2="256" />
        <line x1="76" y1="148" x2="104" y2="164" />
        <line x1="148" y1="76" x2="164" y2="104" />
      </g>

      {/* Hour hand — drawn pointing up, rotated by hourAngle */}
      <g transform={`rotate(${hourAngle} 256 256)`}>
        <line
          x1="256" y1="256" x2="256" y2="128"
          stroke="#4a3728" strokeWidth="14" strokeLinecap="round"
        />
      </g>

      {/* Minute hand — drawn pointing up, rotated by minuteAngle */}
      <g transform={`rotate(${minuteAngle} 256 256)`}>
        <line
          x1="256" y1="256" x2="256" y2="106"
          stroke="#4a3728" strokeWidth="10" strokeLinecap="round"
        />
      </g>

      {/* Center dot — on top of hands */}
      <circle cx="256" cy="256" r="12" fill="#4a3728" />

      {/* Key — second hand. Baked 45° rotation retained; ticks once per second */}
      <g transform={`translate(256 256) rotate(${secondAngle})`}>
        <circle cx="0" cy="0" r="48" fill="none" stroke="#b45309" strokeWidth="16" />
        <line x1="48" y1="0" x2="180" y2="0" stroke="#b45309" strokeWidth="14" strokeLinecap="round" />
        <line x1="140" y1="0" x2="140" y2="26" stroke="#b45309" strokeWidth="12" strokeLinecap="round" />
        <line x1="165" y1="0" x2="165" y2="20" stroke="#b45309" strokeWidth="12" strokeLinecap="round" />
      </g>
    </svg>
  );
}
