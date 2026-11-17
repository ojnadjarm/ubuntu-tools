/* The well's capsules: one short run down a rail when a brief goes out, one up when a report comes back; nothing is drawn at rest and nothing loops. */
import * as T from "../../../vendor/three.sub.js";

const MOVE = 1.5, HOLD = 0.8, GAP = 0.5, R = 0.05, H = 0.17, SEG = 10;
const VS = `varying float vY; void main(){ vY = position.y; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;
const FS = `uniform vec3 uC; varying float vY; void main(){ gl_FragColor = vec4(uC * (0.8 + 2.2 * vY), 1.0); }`;

/* A capsule standing on y: a tube closed by two cones. */
function shape() {
  const P = [0, -H / 2, 0, 0, H / 2, 0], I = [], rings = [[-H / 2 + R * 0.6, R], [H / 2 - R * 0.6, R]];
  rings.forEach(([y, r]) => { for (let i = 0; i < SEG; i++) { const a = (i / SEG) * Math.PI * 2; P.push(r * Math.sin(a), y, r * Math.cos(a)); } });
  for (let i = 0; i < SEG; i++) { const a = 2 + i, b = 2 + ((i + 1) % SEG), c = a + SEG, d = b + SEG; I.push(a, b, d, a, d, c, 0, b, a, 1, c, d); }
  const g = new T.BufferGeometry();
  g.setAttribute("position", new T.BufferAttribute(new Float32Array(P), 3)); g.setIndex(I);
  return g;
}

/* capsules(scene, colours) → {rails(list), fire(events), step(dt)}; rails = [{a, b}] top and foot of each tube, events = [{dir: "out"|"back"}]; step is true while a capsule moves. */
export function capsules(scene, colours) {
  const geo = shape(), runs = [], calm = matchMedia("(prefers-reduced-motion: reduce)");
  let rails = [], n = 0;
  const end = (r) => { scene.remove(r.m); r.m.material.dispose(); };
  return {
    rails(list) { rails = list; if (!list.length) runs.splice(0).forEach(end); },
    fire(events) {
      if (!rails.length || calm.matches) return;
      events.forEach((e, i) => {
        const m = new T.Mesh(geo, new T.ShaderMaterial({ uniforms: { uC: { value: new T.Vector3(...colours[e.dir]) } }, vertexShader: VS, fragmentShader: FS }));
        m.frustumCulled = false; m.visible = false; scene.add(m);
        runs.push({ m, rail: rails[n++ % rails.length], back: e.dir === "back", t: -i * GAP });
      });
    },
    step(dt) {
      for (const r of [...runs]) {
        r.t += dt;
        const k = Math.max(0, Math.min(1, r.t / MOVE)), f = k * k * (3 - 2 * k), [a, b] = r.back ? [r.rail.b, r.rail.a] : [r.rail.a, r.rail.b];
        r.m.visible = r.t >= 0; r.m.position.set(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f);
        if (r.t > MOVE + (r.back ? HOLD : 0)) { end(r); runs.splice(runs.indexOf(r), 1); }
      }
      return runs.length > 0;
    },
  };
}
