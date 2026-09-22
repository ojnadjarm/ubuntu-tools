/* WebGL backdrop: one continuous sparse amber lattice, a region of it per screen.
   Source for static/lattice.js — rebuild with ./build.sh after editing. */
import { AdditiveBlending, BufferAttribute, BufferGeometry, Color, ColorManagement, FogExp2, Group, LinearSRGBColorSpace, LineBasicMaterial, LineSegments, PerspectiveCamera, Points, PointsMaterial, Scene, Vector3, WebGLRenderer } from 'three';
const T = { AdditiveBlending, BufferAttribute, BufferGeometry, Color, ColorManagement, FogExp2, Group, LinearSRGBColorSpace, LineBasicMaterial, LineSegments, PerspectiveCamera, Points, PointsMaterial, Scene, Vector3, WebGLRenderer };
T.ColorManagement.enabled = false;
(function () {
"use strict";
var cv = document.getElementById('bg');
if (!cv || !T.WebGLRenderer) { if (cv) cv.style.display = 'none'; return; }

var mq = matchMedia('(prefers-reduced-motion: reduce)');
var reduce = function () { return mq.matches; };

var renderer;
try {
  renderer = new T.WebGLRenderer({ canvas: cv, antialias: false, alpha: true, powerPreference: 'low-power' });
} catch (e) { cv.style.display = 'none'; return; }
renderer.outputColorSpace = T.LinearSRGBColorSpace;

var AMBER = new T.Color(0xffb000);
var scene = new T.Scene();
scene.fog = new T.FogExp2(0x000000, 0.018);
var cam = new T.PerspectiveCamera(58, 1, 0.1, 260);

var narrow = innerWidth < 620;
var NODES = narrow ? 170 : 380;
var SPAN_X = 44, SPAN_Y = 26, SPAN_Z = 160;

var pts = [], i, j;
for (i = 0; i < NODES; i++) {
  pts.push(new T.Vector3((Math.random() - 0.5) * SPAN_X, (Math.random() - 0.5) * SPAN_Y, -Math.random() * SPAN_Z));
}
var segs = [];
for (i = 0; i < NODES; i++) {
  var near = [];
  for (j = 0; j < NODES; j++) {
    if (i === j) continue;
    var d = pts[i].distanceTo(pts[j]);
    if (d < 15) near.push([d, j]);
  }
  near.sort(function (a, b) { return a[0] - b[0]; });
  for (var k = 0; k < Math.min(2, near.length); k++) {
    if (near[k][1] < i) continue;
    segs.push(pts[i], pts[near[k][1]]);
  }
}

var lineGeo = new T.BufferGeometry().setFromPoints(segs);
var lineCol = new Float32Array(segs.length * 3);
for (i = 0; i < segs.length; i++) {
  var b = 0.12 + 0.55 * Math.max(0, 1 + segs[i].z / SPAN_Z);
  lineCol[i * 3] = AMBER.r * b; lineCol[i * 3 + 1] = AMBER.g * b; lineCol[i * 3 + 2] = AMBER.b * b;
}
lineGeo.setAttribute('color', new T.BufferAttribute(lineCol, 3));
var lineMat = new T.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.55, fog: true,
                                        blending: T.AdditiveBlending, depthWrite: false });
scene.add(new T.Group());
var graph = scene.children[0];
graph.add(new T.LineSegments(lineGeo, lineMat));

var nodeGeo = new T.BufferGeometry().setFromPoints(pts);
var nodeCol = new Float32Array(NODES * 3);
var nodeBase = new Float32Array(NODES);
for (i = 0; i < NODES; i++) nodeBase[i] = 0.34 + 0.66 * Math.pow(Math.random(), 2);
nodeGeo.setAttribute('color', new T.BufferAttribute(nodeCol, 3));
var nodeMat = new T.PointsMaterial({ size: narrow ? 1.8 : 2.2, vertexColors: true, transparent: true,
                                     opacity: 0.95, fog: true, sizeAttenuation: false,
                                     blending: T.AdditiveBlending, depthWrite: false });
graph.add(new T.Points(nodeGeo, nodeMat));

/* one region of the graph per screen */
var REGION = {
  's-sites':    { x: 0,   y: 1.5, z: -6,  ry: 0.00, rx: 0.00 },
  's-services': { x: -13, y: 4,   z: -38, ry: 0.16, rx: -0.05 },
  's-files':    { x: 12,  y: -3,  z: -66, ry: -0.16, rx: 0.05 },
  's-plans':    { x: -6,  y: -6,  z: -96, ry: 0.08, rx: 0.08 },
  's-machine':  { x: 10,  y: 2,   z: -126, ry: -0.08, rx: -0.04 }
};
var target = Object.assign({}, REGION['s-sites']);
var pos = Object.assign({}, REGION['s-sites']);
var pulse = 0, travel = 0;

window.__lat = {
  go: function (to) {
    target = Object.assign({}, REGION[to] || REGION['s-sites']);
    pulse = 1; travel = 1;
    if (reduce()) { pos = Object.assign({}, target); pulse = 0; draw(); }
    wake();
  },
  snap: function (to) {
    var r = REGION[to] || REGION['s-sites'];
    target = Object.assign({}, r); pos = Object.assign({}, r); pulse = 0; draw();
  }
};

var px = 0, py = 0, tpx = 0, tpy = 0;
addEventListener('pointermove', function (e) {
  tpx = (e.clientX / innerWidth - 0.5) * 2;
  tpy = (e.clientY / innerHeight - 0.5) * 2;
  wake();
}, { passive: true });

function resize() {
  var w = innerWidth, h = innerHeight;
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, w < 620 ? 1.5 : 2));
  renderer.setSize(w, h, false);
  cam.aspect = w / h; cam.updateProjectionMatrix();
}
addEventListener('resize', function () { resize(); draw(); wake(); });
resize();

var t0 = performance.now();
function draw() {
  var t = (performance.now() - t0) * 0.001;
  var ease = 0.045 + 0.06 * travel;
  pos.x += (target.x - pos.x) * ease;
  pos.y += (target.y - pos.y) * ease;
  pos.z += (target.z - pos.z) * ease;
  pos.ry += (target.ry - pos.ry) * ease;
  pos.rx += (target.rx - pos.rx) * ease;
  px += (tpx - px) * 0.05; py += (tpy - py) * 0.05;

  cam.position.set(pos.x + px * 3.2, pos.y - py * 2.2, pos.z + 16 + Math.sin(t * 0.12) * 1.2);
  cam.rotation.set(pos.rx - py * 0.045, pos.ry + px * 0.05, 0);
  graph.rotation.y = Math.sin(t * 0.045) * 0.05;
  graph.rotation.x = Math.cos(t * 0.035) * 0.03;

  lineMat.opacity = 0.55 * (1 - pulse * 0.88);
  var col = nodeGeo.attributes.color.array;
  for (var n = 0; n < NODES; n++) {
    var flare = pulse * (0.55 + 0.45 * Math.sin(t * 5 + n * 0.7));
    var b = Math.min(1.25, nodeBase[n] * (0.55 + 0.45 * Math.sin(t * 0.5 + n)) + flare);
    col[n * 3] = AMBER.r * b; col[n * 3 + 1] = AMBER.g * b; col[n * 3 + 2] = AMBER.b * b;
  }
  nodeGeo.attributes.color.needsUpdate = true;

  pulse *= 0.93; if (pulse < 0.003) pulse = 0;
  travel *= 0.96; if (travel < 0.01) travel = 0;
  renderer.render(scene, cam);
}

/* loop: paused when hidden, paused when idle, off under reduced motion */
var raf = null, idleAt = performance.now() + 45000;
function frame() {
  raf = null;
  if (reduce() || document.hidden) return;
  draw();
  if (performance.now() > idleAt && pulse === 0 && travel === 0 &&
      Math.abs(tpx - px) < 0.01 && Math.abs(tpy - py) < 0.01) return;
  raf = requestAnimationFrame(frame);
}
function wake() {
  idleAt = performance.now() + 45000;
  if (!raf && !reduce() && !document.hidden) raf = requestAnimationFrame(frame);
}
document.addEventListener('visibilitychange', function () { if (!document.hidden) wake(); });
addEventListener('keydown', wake, { passive: true });
addEventListener('pointerdown', wake, { passive: true });
mq.addEventListener && mq.addEventListener('change', function () {
  if (reduce()) { if (raf) cancelAnimationFrame(raf); raf = null; pulse = 0; travel = 0;
                  pos = Object.assign({}, target); draw(); }
  else wake();
});

draw();
if (!reduce()) wake();
})();
