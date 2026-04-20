import { useRef, useEffect } from "react";
import { useTotpClock, getTimeLeft } from "@/features/vault/hooks/use-totp-clock";

interface CountdownRingProps {
  period: number;
  size: number;
  radius: number;
  strokeWidth?: number;
  children: React.ReactNode;
}

export function CountdownRing({ period, size, radius, strokeWidth = 2.5, children }: CountdownRingProps) {
  const epoch = useTotpClock();
  const timeLeft = getTimeLeft(epoch, period);
  const circumference = 2 * Math.PI * radius;
  const circleRef = useRef<SVGCircleElement>(null);
  const lastPeriodStart = useRef(-1);

  // Sync animation only at period boundaries or on mount
  useEffect(() => {
    const el = circleRef.current;
    if (!el) return;

    const periodStart = Math.floor(epoch / period) * period;
    if (periodStart === lastPeriodStart.current) return;
    lastPeriodStart.current = periodStart;

    // Reset animation by removing and re-adding it
    el.style.animation = "none";
    // Force reflow
    void el.getBBox();
    const elapsed = epoch - periodStart;
    // steps(period) — one discrete step per second. Avoids 60fps repaint of
    // stroke-dashoffset, which is expensive and pointless for a 1 Hz countdown.
    el.style.animation = `countdown-ring ${period}s steps(${period}) infinite`;
    el.style.animationDelay = `-${elapsed}s`;
  }, [epoch, period]);

  const isUrgent = timeLeft <= 5;
  const cx = size / 2;
  const cy = size / 2;

  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg
        className="absolute inset-0 -rotate-90"
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
      >
        <circle
          cx={cx} cy={cy} r={radius}
          fill="none"
          className="stroke-muted"
          strokeWidth={strokeWidth}
        />
        <circle
          ref={circleRef}
          cx={cx} cy={cy} r={radius}
          fill="none"
          stroke="currentColor"
          className={isUrgent ? "text-red-500" : "text-primary"}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          style={{
            "--ring-circumference": circumference,
          } as React.CSSProperties}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        {children}
      </div>
    </div>
  );
}
