/* Familiars shaders: banded toon with rim light over skinned parts, the inverted-hull ink outline, and the composite of the creature target into the HDR scene. */
export const body = (bones) => `precision highp float;
in vec3 position, normal, aCol, aShade;
in vec4 aP;
uniform mat4 uB[${bones}];
uniform vec2 uRes; uniform vec3 uZ;
out vec3 vN, vCol, vShade; out vec3 vK;
void main(){
  mat4 M = uB[int(aP.x + 0.5)];
  vec4 v = M * vec4(position, 1.0);
  vN = mat3(M) * normal; vCol = aCol; vShade = aShade; vK = aP.yzw;
  gl_Position = vec4(v.xy / uRes * 2.0 - 1.0, uZ.x - v.z * uZ.y, 1.0);
}`;

export const BODY_FS = `precision highp float;
in vec3 vN, vCol, vShade, vK;
uniform vec4 uTint; uniform vec3 uPad; uniform float uDim, uScr, uFade;
out vec4 o;
const vec3 L = vec3(0.4472, 0.8305, 0.4898), RIM = vec3(0.55, 1.0, 0.78);
void main(){
  if (vK.z > 2.5) { o = vec4(uPad, 1.0) * uFade; return; }
  vec3 n = normalize(vN) * (gl_FrontFacing ? 1.0 : -1.0);
  float d = dot(n, L) * 0.5 + 0.5;
  float t = smoothstep(0.43, 0.47, d) * 0.62 + smoothstep(0.76, 0.8, d) * 0.38;
  vec3 c = mix(vShade, vCol, t);
  float r = pow(1.0 - max(n.z, 0.0), 3.0) * smoothstep(0.35, 0.75, d + n.y * 0.3);
  c += RIM * vK.x * r * 0.55 + vCol * vK.y;
  if (vK.z > 0.5 && vK.z < 1.5) c = mix(c, uTint.rgb * (0.35 + 0.65 * t), uTint.a) * uDim;
  if (vK.z > 1.5) c *= uScr;
  o = vec4(c, 1.0) * uFade;
}`;

export const hull = (bones) => `precision highp float;
in vec3 position, normal;
in vec4 aP; in float aO;
uniform mat4 uB[${bones}];
uniform vec2 uRes; uniform vec3 uZ;
void main(){
  mat4 M = uB[int(aP.x + 0.5)];
  if (aO < 0.5 || dot(M[0].xyz, M[0].xyz) < 1e-6) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
  vec4 v = M * vec4(position, 1.0);
  v.xyz += normalize(mat3(M) * normal) * uZ.z;
  gl_Position = vec4(v.xy / uRes * 2.0 - 1.0, uZ.x - v.z * uZ.y, 1.0);
}`;
export const HULL_FS = `precision highp float;
uniform float uFade;
out vec4 o;
void main(){ o = vec4(0.01, 0.045, 0.03, 1.0) * uFade; }`;

/* The creature target holds display-space colour premultiplied by coverage; the scene wants linear light. */
export const COMP = `precision highp float;
uniform sampler2D uTex; uniform vec2 uRes; uniform float uGain;
out vec4 o;
void main(){
  vec4 c = texture(uTex, gl_FragCoord.xy / uRes);
  if (c.a < 0.004) discard;
  o = vec4(pow(c.rgb / c.a, vec3(2.2)) * uGain * c.a, c.a);
}`;
