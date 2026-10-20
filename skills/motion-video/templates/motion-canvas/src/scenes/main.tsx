import {Circle, Line, makeScene2D, Rect, Txt} from '@motion-canvas/2d';
import {all, createRef, easeInOutCubic, easeOutBack, range, sequence, waitFor} from '@motion-canvas/core';
import {FONTS, PALETTE} from '../brand';

/** Graph-style explainer beat: nodes pop in, edges draw, title types on, then collapse. */
export default makeScene2D(function* (view) {
  const colors = [...PALETTE.accent, PALETTE.paper, PALETTE.good];
  const nodes = range(5).map(() => createRef<Circle>());
  const edges = range(4).map(() => createRef<Line>());
  const title = createRef<Txt>();
  const bar = createRef<Rect>();
  const pos = range(5).map(i => [-640 + i * 320, i % 2 ? 120 : -120] as [number, number]);

  view.add(
    <>
      {edges.map((r, i) => (
        <Line ref={r} points={[pos[i], pos[i + 1]]} stroke={PALETTE.muted} lineWidth={10} lineCap={'round'} end={0} />
      ))}
      {nodes.map((r, i) => (
        <Circle ref={r} position={pos[i]} size={110} fill={colors[i]} scale={0} />
      ))}
      <Txt ref={title} y={330} fontFamily={FONTS.display} fontWeight={800} fontSize={96} fill={PALETTE.paper} text={''} />
      <Rect ref={bar} y={410} width={0} height={10} radius={5} fill={PALETTE.accent[1]} />
    </>,
  );

  yield* sequence(0.15, ...nodes.map(n => n().scale(1, 0.6, easeOutBack)));
  yield* sequence(0.2, ...edges.map(e => e().end(1, 0.5, easeInOutCubic)));
  yield* all(title().text('MOTION CANVAS', 1.2), bar().width(780, 1.2, easeInOutCubic));
  yield* all(...nodes.map((n, i) => n().position.y(-n().position.y(), 1.2, easeInOutCubic)));
  yield* waitFor(0.6);
  yield* all(
    ...nodes.map(n => n().scale(0, 0.6, easeInOutCubic)),
    ...edges.map(e => e().start(1, 0.6, easeInOutCubic)),
    title().opacity(0, 0.6),
    bar().width(0, 0.6, easeInOutCubic),
  );
});
