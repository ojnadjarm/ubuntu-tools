import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {FONTS, PALETTE} from './brand';

export type TitleProps = {title: string; subtitle: string; fps: number; seconds: number; cuts: number[]; spans?: [number, number][]};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic)} as const;

/** Film frame shown at render frame k when only the inclusive `spans` render, back to back. */
const spanFrame = (k: number, spans: [number, number][] = []) => {
  for (const [a, b] of spans) {
    if (k <= b - a) return a + k;
    k -= b - a + 1;
  }
  return k;
};

/** Transparent overlay: spring title over shot 1, accent lower third over the last shot. */
export const Title = ({title, subtitle, cuts, spans}: TitleProps) => {
  const frame = spanFrame(useCurrentFrame(), spans);
  const {fps, width, height, durationInFrames} = useVideoConfig();
  const s = Math.min(width / 1920, height / 1080);
  const shadow = `0 ${4 * s}px ${24 * s}px rgba(0,0,0,0.55)`;
  const titleOut = interpolate(frame, [cuts[0] * fps - 0.5 * fps, cuts[0] * fps - 0.1 * fps], [1, 0], clamp);
  const lowIn = Math.round(cuts[cuts.length - 1] * fps + 0.2 * fps);
  const low = spring({frame: frame - lowIn, fps, config: {damping: 14}});
  const lowOut = interpolate(frame, [durationInFrames - 0.6 * fps, durationInFrames - 0.1 * fps], [1, 0], clamp);
  return (
    <AbsoluteFill style={{fontFamily: FONTS.display}}>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: titleOut}}>
        <div style={{display: 'flex', gap: 6 * s, transform: `translateY(${-height * 0.28}px)`}}>
          {title.split('').map((ch, i) => {
            const p = spring({frame: frame - 4 - i * 2, fps, config: {damping: 13}});
            return (
              <span
                key={i}
                style={{
                  fontSize: 150 * s,
                  fontWeight: 800,
                  letterSpacing: 8 * s,
                  color: PALETTE.paper,
                  textShadow: shadow,
                  opacity: p,
                  transform: `translateY(${(1 - p) * 60 * s}px)`,
                }}
              >
                {ch}
              </span>
            );
          })}
        </div>
      </AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: 96 * s,
          bottom: 110 * s,
          display: 'flex',
          alignItems: 'center',
          gap: 22 * s,
          opacity: low * lowOut,
          transform: `translateX(${(1 - low) * -80 * s}px)`,
        }}
      >
        <div style={{width: 10 * s, height: 84 * s, background: PALETTE.accent[0], borderRadius: 5 * s}} />
        <div style={{color: PALETTE.paper, textShadow: shadow}}>
          <div style={{fontSize: 52 * s, fontWeight: 700}}>{title}</div>
          <div style={{fontSize: 30 * s, fontWeight: 400, opacity: 0.85}}>{subtitle}</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
