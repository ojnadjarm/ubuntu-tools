/* A full-screen shader eye: the uniforms every variant shares, fed from the life model each frame. */
import { atlas } from "./atlas.js";

export function shaderVariant(name, fs) {
  let mesh, U;
  return {
    name,
    init({ T, quad }) {
      U = { uRes: { value: new T.Vector2() }, uEye: { value: new T.Vector3() }, uCam: { value: new T.Vector2() }, uGaze: { value: new T.Vector3(0, 0, 1) },
        uLid: { value: new T.Vector4(0.4, 0.3, 0, 0) }, uFlash: { value: new T.Vector4() }, uPupil: { value: 0.3 }, uTime: { value: 0 }, uAct: { value: 0.3 },
        uQ: { value: 2 }, uAtlas: { value: atlas() } };
      mesh = quad(fs, U);
    },
    step(S, t, dt, life) {
      const v = life.view();
      U.uGaze.value.set(...v.gaze); U.uLid.value.set(...v.lid); U.uFlash.value.set(...v.flash); U.uCam.value.set(...v.cam);
      U.uPupil.value = v.pupil; U.uAct.value = v.act; U.uTime.value = t; U.uQ.value = S.q;
      return false;
    },
    draw(r, cam, S) { U.uRes.value.set(S.hdr.width, S.hdr.height); U.uEye.value.set(S.eye.x, S.eye.y, S.eye.r); r.render(mesh, cam); },
  };
}
