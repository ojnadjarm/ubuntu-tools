"""Stage lod: LOD1..n glTF files simplified from the exported LOD0 with gltfpack (skin and morphs kept), tris per level."""
import json
import struct
import subprocess

NAME = 'lod'
SLACK = 1.05


def glb_json(path):
    d = open(path, 'rb').read()
    return json.loads(d[20:20 + struct.unpack('<I', d[12:16])[0]])


def glb_stats(path):
    """Triangles over every primitive (indexed or not), skin joints and the most morph targets on one primitive."""
    g = glb_json(path)
    acc = g.get('accessors', [])
    prims = [p for m in g.get('meshes', []) for p in m['primitives']]
    return {'tris': sum(acc[p['indices'] if 'indices' in p else p['attributes']['POSITION']]['count'] // 3 for p in prims),
            'joints': len({j for s in g.get('skins', []) for j in s['joints']}),
            'morph_targets': max((len(p.get('targets', [])) for p in prims), default=0)}


def simplify(src, dst, ratio, aggressive=False):
    subprocess.run(['gltfpack', '-i', src, '-o', dst, '-si', str(ratio), '-noq', '-kn', '-km'] + (['-sa'] if aggressive else []),
                   check=True, capture_output=True)
    return glb_stats(dst)


def run(ctx):
    a = ctx.spec.get('asset', {})
    glb = ctx.files.get('glb')
    if not glb:
        return {'skipped': True}
    ctx.lods = {'0': {'file': glb, 'ratio': 1.0, **glb_stats(glb)}}
    t0 = ctx.lods['0']['tris']
    for i, ratio in enumerate(a.get('lods', []), 1):
        path = str(ctx.out / f'{ctx.id}_LOD{i}.glb')
        st = simplify(glb, path, ratio)
        if st['tris'] > ratio * SLACK * t0:
            st = dict(simplify(glb, path, ratio, aggressive=True), aggressive=True)
        ctx.lods[str(i)] = {'file': path, 'ratio': ratio, **st}
    return {'stub': False, 'tris': {k: v['tris'] for k, v in ctx.lods.items()},
            'achieved': {k: round(v['tris'] / max(t0, 1), 3) for k, v in ctx.lods.items()},
            'joints': {k: v['joints'] for k, v in ctx.lods.items()},
            'morph_targets': {k: v['morph_targets'] for k, v in ctx.lods.items()}}
