"""Encode each rendered PNG sequence to H.264 mp4 (still -> jpg), mux talk audio, cap the size, delete the PNGs."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

CRF = 18
AUDIO_KBPS = 128


def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *map(str, args)], check=True)


def h264(frames, fps, dst, audio=None, kbps=None):
    """BT.709 H.264 high, yuv420p, faststart; CRF by default, a capped bitrate when kbps is given."""
    rate = ['-crf', CRF] if kbps is None else ['-b:v', f'{kbps}k', '-maxrate', f'{kbps}k', '-bufsize', f'{2 * kbps}k']
    a_in = ['-i', audio] if audio else []
    a_out = ['-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-b:a', f'{AUDIO_KBPS}k', '-shortest'] if audio else []
    ffmpeg('-framerate', fps, '-pattern_type', 'glob', '-i', frames / '*.png', *a_in,
           '-c:v', 'libx264', '-preset', 'slow', *rate, '-profile:v', 'high', '-pix_fmt', 'yuv420p',
           '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', *a_out,
           '-movflags', '+faststart', dst)


def encode_clip(frames, r, dst, audio, cap_mb):
    h264(frames, r['fps'], dst, audio)
    mb = dst.stat().st_size / 1e6
    if mb > cap_mb:
        seconds = r['frames'] / r['fps']
        kbps = int(cap_mb * 8000 * 0.92 / seconds) - (AUDIO_KBPS if audio else 0)
        h264(frames, r['fps'], dst, audio, kbps)
    return dst


def encode(out, keep_frames=False):
    out = Path(out)
    build_path = out / 'build.json'
    build = json.loads(build_path.read_text())
    cap_mb = build['spec'].get('qa', {}).get('thresholds', {}).get('mp4_mb', 20)
    (out / 'renders').mkdir(exist_ok=True)
    for sid, r in build['renders'].items():
        frames = Path(r['frames_dir'])
        pngs = sorted(frames.glob('*.png'))
        if not pngs:
            continue
        if r['frames'] == 1:
            dst = out / 'renders' / f'{sid}.jpg'
            ffmpeg('-i', pngs[0], '-q:v', 2, dst)
        else:
            audio = build['files'].get(f"audio:{r.get('clip')}")
            dst = encode_clip(frames, r, out / 'renders' / f'{sid}.mp4', audio, cap_mb)
            r['audio'] = bool(audio)
        r['file'], r['mb'] = str(dst), round(dst.stat().st_size / 1e6, 3)
        if not keep_frames:
            shutil.rmtree(frames)
    build_path.write_text(json.dumps(build, indent=1))
    return build['renders']


if __name__ == '__main__':
    for sid, r in encode(sys.argv[1], '--keep-frames' in sys.argv).items():
        print(f"char3d encode: {sid} {r.get('file')} {r.get('mb')} MB")
