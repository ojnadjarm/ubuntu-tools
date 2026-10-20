"""mvlib: the one ffprobe probe and colour-family table shared by mv-diff, mv-quality and mv-review."""
import json
import re
import subprocess

FAMILY = {'bt2020nc': 'bt2020', 'bt2020c': 'bt2020', 'bt2020-10': 'bt2020', 'bt2020-12': 'bt2020',
          'smpte2084': 'bt2020', 'arib-std-b67': 'bt2020', 'smpte170m': 'bt601', 'bt470bg': 'bt601'}
SCALE_MATRICES = ('bt709', 'fcc', 'bt601', 'smpte240m', 'bt2020')


class MvError(Exception):
    """A file mvlib cannot read as video."""


def family(tag):
    """Colour family (bt709, bt601, bt2020, ...) of an ffprobe space/transfer/primaries tag."""
    return FAMILY.get(tag, tag)


def probe(path):
    """Duration, size, frame rate, pixel format, audio flag and colour tags of the first video stream."""
    r = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                        'format=duration:stream=codec_type,width,height,r_frame_rate,pix_fmt,'
                        'color_space,color_transfer,color_primaries,color_range', '-of', 'json', path],
                       capture_output=True, text=True)
    if r.returncode:
        raise MvError(f'cannot read {path}\n{r.stderr.strip()}')
    d = json.loads(r.stdout or '{}')
    streams = d.get('streams', [])
    v = next((s for s in streams if s['codec_type'] == 'video'), None)
    if v is None:
        raise MvError(f'no video stream in {path}')
    n, den = v['r_frame_rate'].split('/')
    pix = v.get('pix_fmt', '')
    cs = v.get('color_space', 'unknown')
    return {'duration': float(d.get('format', {}).get('duration', 0)), 'width': v['width'], 'height': v['height'],
            'fps': v['r_frame_rate'], 'rate': int(n) / int(den),
            'pix': 'yuv420p10le' if re.search(r'1[02]', pix) else 'yuv420p',
            'audio': any(s['codec_type'] == 'audio' for s in streams),
            'color': {k: v.get(k, 'unknown') for k in ('color_space', 'color_transfer', 'color_primaries', 'color_range')},
            'matrix': 'bt709' if cs == 'unknown' else family(cs) if family(cs) in SCALE_MATRICES else 'bt601',
            'range': 'pc' if v.get('color_range') == 'pc' else 'tv',
            'untagged': cs == 'unknown' and pix.startswith(('yuv', 'nv'))}
