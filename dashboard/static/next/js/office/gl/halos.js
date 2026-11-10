/* Soft additive halos round lit lamps: one Points draw. */
import * as T from "../../../vendor/three.sub.js";

/* halos(stage) → set(lamps), lamps = [{x, y, z, col, r, halo}]; a lamp with no halo is skipped. */
export function halos(S) {
  const geo = new T.BufferGeometry(), U = { uH: { value: 1 } }, size = new T.Vector2();
  const mat = new T.ShaderMaterial({ uniforms: U, transparent: true, premultipliedAlpha: true, depthWrite: false, blending: T.AdditiveBlending,
    vertexShader: `attribute vec4 glow; uniform float uH; varying vec3 vC; void main(){ vec4 mv = modelViewMatrix * vec4(position, 1.0); vC = glow.rgb; gl_PointSize = glow.a * uH / -mv.z; gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `varying vec3 vC; void main(){ float d = length(gl_PointCoord - 0.5) * 2.0; float a = max(0.0, 1.0 - d); gl_FragColor = vec4(vC * a * a * a, 0.0); }` });
  const pts = new T.Points(geo, mat);
  pts.frustumCulled = false; S.scene.add(pts);
  pts.onBeforeRender = (r) => { U.uH.value = r.getDrawingBufferSize(size).y * S.cam.projectionMatrix.elements[5] * 0.5; };
  return (lamps) => {
    const L = lamps.filter((l) => l.halo);
    geo.setAttribute("position", new T.BufferAttribute(new Float32Array(L.flatMap((l) => [l.x, l.y, l.z])), 3));
    geo.setAttribute("glow", new T.BufferAttribute(new Float32Array(L.flatMap((l) => [l.col[0] * l.halo, l.col[1] * l.halo, l.col[2] * l.halo, l.r * 1.5])), 4));
  };
}
