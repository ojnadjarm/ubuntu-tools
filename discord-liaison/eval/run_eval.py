"""Run the discord-liaison eval: one tool-less `claude -p` decision per fixture, results as JSONL."""
import argparse, concurrent.futures as cf, json, os, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from liaison.context import ContextRenderer, self_line  # noqa: E402
FOOTER = '''
## EVAL MODE
You are in eval mode: do not run tools; output only JSON {"reply": bool, "text": str|null, "react": str|null, "escalate": bool, "reasoning_short": str}.
Decide what you would do for the inbox below, as if `discord-liaison inbox` had just printed it.
- reply: whether you would post a reply. text: the one reply you would post now (for a task you start: the ack you post before the work; for an escalation: the ack); null when reply is false.
- react: the reaction you would put on the last message now: "👀", "✅" or null.
- escalate: whether you would run `discord-liaison escalate` for it.
- You cannot run Read here: each image's content is given as [eval: ...] as if you had looked at it.
{history_note}'''


def attrs(**kv):
    return ' '.join(f'{k}="{v}"' for k, v in kv.items())


def render_image(mid, i, img):
    path = f'state/work/{mid}-{i}.png'
    note = f'GIF, {img["frames"]} frames, {img["secs"]} s' if img.get('kind') == 'gif' else ''
    return path, (f'\n[{path}: {note}]' if note else '') + f'\n[eval: {path} shows {img["shows"]}]'


HISTORY_NOTE = ('- "Earlier in this channel" lists messages already handled (context only); author "agents" with '
                'you="true" is you.\n')


def footer(context):
    return FOOTER.replace('{history_note}', '' if context == 'liaison' else HISTORY_NOTE)


def liaison_block(fx):
    """The production <context> block (liaison.context) for the fixture's history, the inbox messages as stubs."""
    c, msgs, ids = fx['context'], [], {}
    for i, h in enumerate(c['history'] + [dict(m, self=False, ts=None) for m in fx['message']]):
        uid = '900' if h['self'] else '1' if h['owner'] else ids.setdefault(h['author'], str(10 + len(ids)))
        msgs.append({'id': h.get('id') or str(1000 + i), 'author': {'id': uid, 'username': h['author'], 'bot': h['bot']},
                     'content': h['content'], 'timestamp': h.get('ts') or '',
                     'attachments': [{'filename': n} for n in h.get('images', []) if isinstance(n, str)],
                     'reactions': [{'emoji': {'name': e}, 'me': True} for e in h.get('acks', [])]})
    name = '#general' if c['channel'] == 'general' else c['title']
    return ContextRenderer('900', owner='1').render([(name, msgs)], [m['id'] for m in fx['message']], self_line(5))


def render(fx, context='full'):
    """The inbox text the liaison would see: context 'full' (past lines), 'liaison' (production block) or 'none'."""
    c, out = fx['context'], []
    if context == 'liaison':
        out.append(liaison_block(fx))
    if context == 'full' and c['history']:
        out.append('Earlier in this channel (oldest first, already handled):')
        for h in c['history']:
            att = f' attachments="{" ".join(h["images"])}"' if h['images'] else ''
            out.append(f'<past {attrs(author=h["author"], bot=str(h["bot"]).lower(), owner=str(h["owner"]).lower(), you=str(h["self"]).lower())}{f' ts="{h["ts"]}"' if h["ts"] else ""}{att}>'
                       f'{h["content"]}</past>')
        out.append('')
    for msg in fx['message']:
        paths, notes = [], ''
        for i, img in enumerate(msg['images'], 1):
            p, nt = render_image(msg['id'], i, img)
            paths.append(p)
            notes += nt
        images = f' images="{" ".join(paths)}"' if paths else ''
        body = msg['content'].replace('</message', '<\\/message')
        out.append(f'<message {attrs(channel=c["channel"], thread=c["thread"], title=c["title"], tags="", project="", route="", author=msg["author"], bot=str(msg["bot"]).lower(), owner=str(msg["owner"]).lower(), id=msg["id"])}{images}>\n'
                   f'{body}{notes}\n</message>')
    out.append(f'{len(fx["message"])} message(s); run `discord-liaison done` after answering them')
    return '\n'.join(out)


def parse(text):
    """First JSON object in the model's text, fences tolerated."""
    i = text.find('{')
    if i < 0:
        raise ValueError('no JSON object')
    return json.JSONDecoder().raw_decode(text[i:])[0]


def call(prompt, model, timeout):
    with tempfile.TemporaryDirectory() as cwd:
        cmd = ['claude', '-p', '--model', model, '--output-format', 'json', '--tools', '', '--safe-mode',
               '--strict-mcp-config', '--no-session-persistence']
        t = time.monotonic()
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        return p, round(time.monotonic() - t, 1)


def run_one(fx, rules, args):
    prompt = rules.rstrip() + '\n' + footer(args.context) + '\n' + render(fx, args.context)
    row = {'id': fx['id'], 'class': fx['class'], 'model': args.model, 'context': args.context}
    try:
        p, secs = call(prompt, args.model, args.timeout)
        row['seconds'] = secs
        env = json.loads(p.stdout)
        row['cost_usd'] = env.get('total_cost_usd')
        row['raw'] = env.get('result', '')
        row['decision'] = parse(row['raw'])
    except Exception as e:
        row['error'] = f'{type(e).__name__}: {e}'
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('prompt_file')
    ap.add_argument('--model', default='sonnet', choices=['sonnet', 'opus'])
    ap.add_argument('--only', default='', help='comma-separated fixture ids')
    ap.add_argument('--jobs', type=int, default=3)
    ap.add_argument('--context', default='liaison', choices=['liaison', 'full', 'none'],
                    help='liaison = the shipped <context> block (T1413); none = only the inbox, like before T1413')
    ap.add_argument('--fixtures', default=os.path.join(HERE, 'fixtures.jsonl'))
    ap.add_argument('--timeout', type=int, default=300)
    ap.add_argument('--show', action='store_true', help='print the prompt of each selected fixture, call nothing')
    ap.add_argument('--out', default='results.jsonl')
    args = ap.parse_args()
    with open(args.prompt_file) as f:
        rules = f.read()
    with open(args.fixtures) as f:
        fixtures = [json.loads(line) for line in f if line.strip()]
    if args.only:
        want = set(args.only.split(','))
        fixtures = [fx for fx in fixtures if fx['id'] in want]
        missing = want - {fx['id'] for fx in fixtures}
        if missing:
            sys.exit(f'unknown fixture ids: {", ".join(sorted(missing))}')
    if args.show:
        for fx in fixtures:
            print(f'===== {fx["id"]}\n{rules.rstrip()}\n{footer(args.context)}\n{render(fx, args.context)}')
        return
    lock = threading.Lock()
    with open(args.out, 'w') as out, cf.ThreadPoolExecutor(args.jobs) as pool:
        for row in pool.map(lambda fx: run_one(fx, rules, args), fixtures):
            with lock:
                out.write(json.dumps(row, ensure_ascii=False) + '\n')
                out.flush()
            print(f'{row["id"]}: {row.get("seconds", "-")} s ${row.get("cost_usd") or 0:.4f} {row.get("error", "ok")}',
                  file=sys.stderr)


if __name__ == '__main__':
    main()
