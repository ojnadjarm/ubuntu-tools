/* The katakana glyph atlas as a mipmapped three.js texture for the eye shaders. */
import * as T from "../vendor/three.lab.js";
import { glyphCanvas } from "./glyphs.js";

export function atlas(cell = 64) {
  const t = new T.CanvasTexture(glyphCanvas(cell));
  t.flipY = false; t.colorSpace = T.NoColorSpace;
  t.minFilter = T.LinearMipmapLinearFilter; t.magFilter = T.LinearFilter; t.generateMipmaps = true;
  return t;
}
