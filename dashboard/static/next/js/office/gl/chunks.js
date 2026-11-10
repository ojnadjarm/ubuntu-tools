/* The static office as one lit-per-vertex mesh per chunk. */
import * as T from "../../../vendor/three.sub.js";

/* chunks(stage) → {set(id, Chunk), drop(id), recolor(id, color), size, verts()}. */
export function chunks(S) {
  const all = new Map(), mat = new T.MeshBasicMaterial({ vertexColors: true });
  const drop = (id) => { const m = all.get(id); if (!m) return; S.scene.remove(m); m.geometry.dispose(); all.delete(id); };
  return {
    set(id, c) {
      drop(id);
      const geo = new T.BufferGeometry();
      geo.setAttribute("position", new T.BufferAttribute(c.position, 3)); geo.setAttribute("color", new T.BufferAttribute(c.color, 3)); geo.setIndex(new T.BufferAttribute(c.index, 1));
      const m = new T.Mesh(geo, mat);
      m.frustumCulled = false; m.matrixAutoUpdate = false; S.scene.add(m); all.set(id, m);
    },
    drop,
    recolor(id, color) { const a = all.get(id).geometry.attributes.color; a.array.set(color); a.needsUpdate = true; },
    get size() { return all.size; },
    verts() { let n = 0; for (const m of all.values()) n += m.geometry.attributes.position.count; return n; },
  };
}
