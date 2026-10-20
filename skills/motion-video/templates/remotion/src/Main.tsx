import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {FONTS, PALETTE} from './brand';

const INK = PALETTE.ink;
const ACCENT = PALETTE.accent;

/** Kinetic title card: staggered spring letters, orbiting bars, wipe out. */
export const Main = () => {
  const frame = useCurrentFrame();
  const {fps, width, height, durationInFrames} = useVideoConfig();
  const s = Math.min(width / 1200, height / 1080);
  const word = 'MOTION';
  const outro = interpolate(frame, [durationInFrames - 45, durationInFrames], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  });
  const hue = interpolate(frame, [0, durationInFrames], [210, 260]);
  return (
    <AbsoluteFill style={{background: `radial-gradient(circle at 30% 30%, hsl(${hue},40%,16%), ${INK} 70%)`}}>
      {ACCENT.map((c, i) => {
        const t = frame / fps;
        const angle = t * (0.6 + i * 0.25) + (i * Math.PI * 2) / 3;
        const r = 330 * s;
        const grow = spring({frame: frame - 10 - i * 8, fps, config: {damping: 14}});
        return (
          <div
            key={c}
            style={{
              position: 'absolute',
              left: width / 2 + Math.cos(angle) * r - 140 * s,
              top: height / 2 + Math.sin(angle) * r * 0.55 - 12 * s,
              width: 280 * s * grow,
              height: 24 * s,
              borderRadius: 12 * s,
              background: c,
              transform: `rotate(${angle + Math.PI / 2}rad)`,
              opacity: 0.9,
              filter: `blur(${(1 - grow) * 8}px)`,
            }}
          />
        );
      })}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', flexDirection: 'row'}}>
        {word.split('').map((ch, i) => {
          const p = spring({frame: frame - 20 - i * 5, fps, config: {damping: 12, mass: 0.7}});
          return (
            <span
              key={i}
              style={{
                fontFamily: `${FONTS.display}, sans-serif`,
                fontWeight: 900,
                fontSize: 220 * s,
                letterSpacing: -6 * s,
                color: PALETTE.paper,
                display: 'inline-block',
                transform: `translateY(${(1 - p) * 140 * s}px) scale(${0.6 + 0.4 * p})`,
                opacity: p,
              }}
            >
              {ch}
            </span>
          );
        })}
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 180 * s}}>
        <div
          style={{
            fontFamily: `${FONTS.mono}, monospace`,
            fontSize: 38 * s,
            color: ACCENT[1],
            opacity: interpolate(frame, [70, 100], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}),
            letterSpacing: 8 * s,
          }}
        >
          {width}×{height} · REMOTION
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: ACCENT[2], clipPath: `inset(0 ${100 - outro * 100}% 0 0)`}} />
    </AbsoluteFill>
  );
};
