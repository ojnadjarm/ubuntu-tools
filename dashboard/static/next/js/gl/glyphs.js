/* Katakana glyphs: the 8×8 atlas (red = sharp glyph, green = its glow, mirrored) as a canvas and a mipmapped texture, and the half-width set for decode type. */
export const GLYPHS = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン0123456789ﾘｸﾀﾇﾆ";
export const KANA = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ";

export function glyphCanvas(cell = 64) {
  const c = document.createElement("canvas");
  c.width = 8 * cell; c.height = 8 * cell;
  const g = c.getContext("2d");
  g.fillStyle = "#000"; g.fillRect(0, 0, c.width, c.height);
  g.textAlign = "center"; g.textBaseline = "middle";
  g.font = `600 ${Math.round(cell * 0.6)}px 'Noto Sans CJK JP','Noto Sans JP','Hiragino Sans','Yu Gothic',sans-serif`;
  g.globalCompositeOperation = "lighter";
  [...GLYPHS].slice(0, 64).forEach((ch, i) => {
    const x = (i % 8) * cell + cell / 2, y = ((i / 8) | 0) * cell + cell / 2;
    g.save(); g.translate(x, y); g.scale(-1, 1);
    g.fillStyle = "#00ff00"; g.shadowColor = "#00ff00"; g.shadowBlur = cell * 0.22; g.fillText(ch, 0, 0);
    g.shadowBlur = 0; g.fillStyle = "#ff0000"; g.fillText(ch, 0, 0);
    g.restore();
  });
  return c;
}

/* The atlas as a three.js texture, made once per page. */
let tex = null;
export function atlas(T) {
  if (tex) return tex;
  tex = new T.CanvasTexture(glyphCanvas(64));
  tex.flipY = false; tex.colorSpace = T.NoColorSpace;
  tex.minFilter = T.LinearMipmapLinearFilter; tex.magFilter = T.LinearFilter; tex.generateMipmaps = true;
  return tex;
}
