/* UI-system shaders on raw WebGL2: the living glyph background and the lens gauge, one full-screen triangle each, no three.js. */
import { PAL, NOISE } from "./glsl.js";
import { glyphCanvas } from "./glyphs.js";

const VS = `#version 300 es
void main(){ vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2); gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0); }`;

const COMMON = `#version 300 es
precision highp float;
uniform vec2 uRes; uniform float uTime, uAct; uniform sampler2D uAtlas;
out vec4 o;
${PAL}
${NOISE}
const float PI2 = 6.2831853;
vec2 glyph(float id, vec2 c, float bl){
  vec2 uv = (vec2(mod(id, 8.0), floor(id / 8.0)) + 0.1 + clamp(c, 0.0, 1.0) * 0.8) / 8.0;
  return textureGrad(uAtlas, uv, vec2(bl * 0.1, 0.0), vec2(0.0, bl * 0.1)).rg;
}
`;

/* Three depths of katakana bokeh with pointer/scroll parallax, a camera dolly, press ripples and a faint aurora; brightness and density follow the data. */
const BG = `${COMMON}
uniform vec2 uPar, uPan; uniform float uDrift, uZoom, uScroll; uniform vec4 uRip[4];
void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float ring = 0.0;
  vec2 push = vec2(0.0);
  for (int i = 0; i < 4; i++) {
    vec4 R = uRip[i];
    float age = uTime - R.z;
    if (R.w <= 0.0 || age < 0.0 || age > 1.6) continue;
    vec2 d = uv - R.xy;
    float l = length(d), w = 0.035 + age * 0.06;
    float k = exp(-pow((l - age * 0.75) / w, 2.0)) * (1.0 - age / 1.6) * R.w;
    ring += k; push += d / max(l, 1e-3) * k * 0.012;
  }
  vec3 c = vec3(0.0);
  float dens = 0.09 + 0.1 * uAct;
  for (int l = 0; l < 3; l++) {
    float fl = float(l), d = 1.0 + fl * 1.3, k = 1.0 + (uZoom - 1.0) / d;
    vec2 q = (uv - push - uPan / d) / k - (uPar * 0.05 + vec2(0.0, -uScroll * 0.4)) / d;
    float sc = mix(2.6, 8.0, fl * 0.5);
    vec2 p = q * sc + vec2(fl * 0.37, -uDrift * mix(0.012, 0.04, fl * 0.5));
    vec2 ci = floor(p), cf = fract(p);
    float h = h12(ci + fl * 31.0);
    if (h > dens * (1.0 + 0.6 * fl)) continue;
    vec2 off = vec2(h12(ci + 7.0), h12(ci + 13.0)) * 0.4 + 0.3;
    vec2 gu = (cf - off) * mix(2.2, 3.0, fl * 0.5) + 0.5;
    float mask = 1.0 - smoothstep(0.3, 0.5, length(gu - 0.5));
    float bl = fl < 0.5 ? 0.62 : fl < 1.5 ? 0.16 : 0.3;
    vec2 g = glyph(floor(h12(ci + 3.0) * 60.0), gu, bl);
    float tw = 0.55 + 0.45 * sin(uTime * (0.3 + 1.6 * h / dens) + h * 600.0);
    float lit = fl < 0.5 ? 0.022 : fl < 1.5 ? 0.09 : 0.03;
    c += mix(VIO, MINT, step(dens * 0.22, h)) * (g.x * 0.7 + g.y * 0.8) * mask * tw * lit * (0.55 + 0.9 * uAct);
  }
  c *= 1.0 + 4.0 * ring;
  c += MINT * ring * 0.03;
  float top = exp(-length((uv - vec2(0.0, 0.62)) * vec2(0.8, 2.4)) * 1.7);
  c += (MINT * 0.5 + VIO * 0.5) * 0.004 * top * (0.6 + 0.7 * uAct);
  c *= smoothstep(1.35, 0.25, length(uv * vec2(0.75, 1.0)));
  c = pow(max(c, 0.0), vec3(1.0 / 2.2)) + (h12(gl_FragCoord.xy + fract(uTime) * 91.0) - 0.5) / 255.0;
  o = vec4(max(c, 0.0), 1.0);
}`;

/* A glass lens gauge: lit bezel, tick ring, a comet arc for the value, a turning glyph ring, the studio catchlight; premultiplied alpha. */
const GAUGE = `${COMMON}
uniform vec2 uLight; uniform float uVal, uPress;
void main(){
  float s = min(uRes.x, uRes.y), px = 2.0 / s;
  vec2 p = (gl_FragCoord.xy - 0.5 * uRes) / (0.5 * s);
  float r = length(p), t = fract(atan(p.x, p.y) / PI2 + 1.0);
  vec2 dir = p / max(r, 1e-4);
  vec3 L = normalize(vec3(uLight, 0.8));
  vec3 col = vec3(0.0);
  float x = (r - 0.925) / 0.055;
  float bez = 1.0 - smoothstep(1.0 - 1.5 * px / 0.055, 1.0, abs(x));
  vec3 n = normalize(vec3(dir * x * 0.85, sqrt(max(1.0 - x * x * 0.72, 0.0))));
  float dif = max(dot(n, L), 0.0), spe = pow(max(dot(reflect(-L, n), vec3(0.0, 0.0, 1.0)), 0.0), 36.0);
  vec3 bezC = vec3(0.01, 0.018, 0.014) + dif * vec3(0.03, 0.07, 0.05) + spe * vec3(0.45, 0.85, 0.65) + MINT * uPress * 0.25 * (1.0 - abs(x));
  float face = 1.0 - smoothstep(0.87 - px, 0.87, r);
  vec3 fc = mix(vec3(0.003, 0.005, 0.004), VIO * 0.028, smoothstep(0.15, 0.87, r));
  float gr = (r - 0.575) / 0.05;
  if (abs(gr) < 1.0) {
    float a = fract(t - uTime * 0.006) * 36.0, id = floor(a), hh = h12(vec2(id, 3.0));
    float on = step(0.3, hh) * (0.6 + 0.4 * sin(uTime * (0.5 + hh) + hh * 40.0));
    vec2 g = glyph(floor(h12(vec2(id, 9.0)) * 60.0), vec2(fract(a), gr * 0.5 + 0.5), 0.06);
    fc += mix(VIO * 0.8, MINT, step(0.45, h12(vec2(id, 5.0)))) * (g.x * 0.9 + g.y * 0.35) * on * (0.12 + 0.18 * uAct);
  }
  float tk = fract(t * 60.0), td = min(tk, 1.0 - tk), m5 = fract(t * 12.0), major = step(min(m5, 1.0 - m5) * 5.0, 0.2);
  float tr = smoothstep(0.745, 0.752, r) * (1.0 - smoothstep(0.79 + 0.03 * major, 0.797 + 0.03 * major, r));
  float tick = tr * (1.0 - smoothstep(0.07, 0.13, td));
  float lit = step(t, uVal);
  fc += tick * mix(vec3(0.05, 0.08, 0.07), MINT * 0.7, lit);
  float arcW = 0.022, ad = abs(r - 0.68);
  float inArc = step(t, uVal), head = uVal * PI2;
  float trail = inArc * mix(0.18, 1.0, pow(clamp(t / max(uVal, 1e-3), 0.0, 1.0), 2.5));
  float core = 1.0 - smoothstep(arcW - px, arcW + px, ad);
  fc += vec3(0.03, 0.05, 0.04) * (1.0 - smoothstep(arcW * 0.35, arcW * 0.35 + px, ad)) * (1.0 - inArc);
  vec3 arc = MINT * (core * trail * 1.1 + exp(-ad / 0.03) * trail * 0.28);
  vec2 hp = 0.68 * vec2(sin(head), cos(head));
  float hd = length(p - hp);
  arc += mix(MINT, vec3(0.9, 1.0, 0.95), 0.5) * (exp(-hd / 0.018) * 1.4 + exp(-hd / 0.09) * 0.35) * step(0.002, uVal);
  fc += arc * (1.0 + uPress * 0.8);
  float da = atan(p.y, p.x) - atan(L.y, L.x);
  da = abs(mod(da + 3.14159265, PI2) - 3.14159265);
  float cres = smoothstep(0.64, 0.8, r) * (1.0 - smoothstep(0.81, 0.865, r)) * exp(-da * da / 0.16);
  fc += vec3(0.7, 1.0, 0.85) * cres * 0.16;
  fc += vec3(0.4, 0.8, 0.6) * 0.03 * (1.0 - smoothstep(0.0, 0.9, length(p - normalize(L.xy + 1e-4) * 0.5)));
  col = fc * face + bezC * bez;
  float alpha = max(face, bez);
  float glow = exp(-max(r - 0.98, 0.0) / 0.03) * (1.0 - alpha) * (0.06 + 0.1 * uPress);
  col += MINT * glow * 0.4;
  alpha = max(alpha, glow);
  col += (h12(gl_FragCoord.xy + uTime) - 0.5) / 255.0 * alpha;
  o = vec4(max(col, 0.0), alpha);
}`;

function compile(gl, type, src) {
  const s = gl.createShader(type);
  gl.shaderSource(s, src); gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
  return s;
}

/* A canvas with one program: draw(w, h, uniforms) sizes the buffer and paints; uniforms are {name: number | array}. */
function surface(canvas, fs, alpha) {
  const gl = canvas.getContext("webgl2", { alpha, premultipliedAlpha: true, antialias: false, depth: false, stencil: false, powerPreference: "high-performance" });
  if (!gl) return null;
  const prog = gl.createProgram();
  gl.attachShader(prog, compile(gl, gl.VERTEX_SHADER, VS)); gl.attachShader(prog, compile(gl, gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
  gl.useProgram(prog);
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, glyphCanvas(64));
  gl.generateMipmap(gl.TEXTURE_2D);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.bindVertexArray(gl.createVertexArray());
  const loc = {};
  const at = (k) => (k in loc ? loc[k] : (loc[k] = gl.getUniformLocation(prog, k)));
  gl.uniform1i(at("uAtlas"), 0);
  return {
    gl,
    draw(w, h, U) {
      if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
      gl.viewport(0, 0, w, h);
      gl.uniform2f(at("uRes"), w, h);
      for (const k in U) {
        const v = U[k], l = at(k);
        if (l == null) continue;
        if (typeof v === "number") gl.uniform1f(l, v);
        else if (v.length === 2) gl.uniform2fv(l, v);
        else gl.uniform4fv(l, v);
      }
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}

export const background = (canvas) => surface(canvas, BG, false);
export const gauge = (canvas) => surface(canvas, GAUGE, true);
