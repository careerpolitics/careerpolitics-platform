import { h } from 'preact';
import { useState, useEffect, useRef } from 'preact/hooks';

export function ExamTimer({ timeRemainingSeconds, onTimeUp }) {
  const [remaining, setRemaining] = useState(timeRemainingSeconds);
  const intervalRef = useRef(null);
  const onTimeUpRef = useRef(onTimeUp);

  // Keep the callback ref current without re-triggering the interval
  useEffect(() => {
    onTimeUpRef.current = onTimeUp;
  }, [onTimeUp]);

  useEffect(() => {
    setRemaining(timeRemainingSeconds);

    intervalRef.current = setInterval(() => {
      setRemaining((prev) => {
        if (prev <= 1) {
          clearInterval(intervalRef.current);
          onTimeUpRef.current?.();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(intervalRef.current);
  }, [timeRemainingSeconds]);

  const hours = Math.floor(remaining / 3600);
  const minutes = Math.floor((remaining % 3600) / 60);
  const seconds = remaining % 60;

  const pad = (n) => String(n).padStart(2, '0');

  const isLow = remaining < 300; // < 5 min
  const isCritical = remaining < 60; // < 1 min

  return (
    <div
      class="fw-bold fs-l"
      style={{
        color: isCritical
          ? 'var(--accent-danger)'
          : isLow
            ? 'var(--accent-warning)'
            : 'inherit',
        fontVariantNumeric: 'tabular-nums',
      }}
    >
      {hours > 0 && `${pad(hours)}:`}
      {pad(minutes)}:{pad(seconds)}
    </div>
  );
}
