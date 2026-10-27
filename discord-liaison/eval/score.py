"""Score run_eval.py results against fixtures.jsonl: deterministic regex and field checks, no LLM grader."""
import argparse, collections, json, os, re, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
GLOBAL = {
    'no_puedo': r'\bno (puedo|soy capaz|me es posible)\b',
    'owner_decides': r'(lo decide (el )?owner|eso (lo )?decide (el )?owner|aprobaci[oó]n del owner)',
    'leak': r'(/home/|~/|\b\d{1,3}(\.\d{1,3}){3}\b|\b[\w.+-]+@[\w-]+\.[a-z]{2,}\b)',
}
TONE = {
    'playful': r'([\U0001F300-\U0001FAFF]|ah[ií] va|me lo merezco|jaja|jeje|😄|😂|😅|🤣|😜|😉|🙃|😎|🤖|😏|🥲|😁|😆|😀|😃|🎉|💪|😺|🦾)',
    'empathetic': r'(corrijo|me equivoqu|perd[oó]n|perdona|disculpa|lo siento|tienes (toda la )?raz[oó]n|entiendo|vaya|uf\b|ups|fallo m[ií]o|culpa m[ií]a|😅|🙏)',
}
EN = set('the and you is are can i to of it this what with for your my that here please sure will'.split())
ES = set('el la de que y en un una es por con para te lo tu mi aquí no se los las me al del ya'.split())


def fold(s):
    return ''.join(c for c in unicodedata.normalize('NFKD', s) if not unicodedata.combining(c)).lower()


def hit(pattern, text):
    flags = re.I | re.M
    return bool(re.search(pattern, text, flags) or re.search(fold(pattern), fold(text), flags))


def english(text):
    words = re.findall(r"[a-záéíóúñü']+", text.lower())
    en, es = sum(w in EN for w in words), sum(w in ES for w in words)
    return en >= 3 and en > es


def check(fx, row):
    """Return (failed checks, informational notes) for one result row."""
    e, fails, info = fx['expect'], [], []
    d = row.get('decision')
    if not isinstance(d, dict):
        return [f'no decision ({row.get("error", "unparsable")})'], info
    reply, text = bool(d.get('reply')), d.get('text') or ''
    if e.get('reply') is not None and reply != e['reply']:
        fails.append(f'reply={reply}, want {e["reply"]}')
    if 'react' in e and d.get('react') != e['react']:
        fails.append(f'react={d.get("react")!r}, want {e["react"]!r}')
    if 'escalate' in e and bool(d.get('escalate')) != e['escalate']:
        fails.append(f'escalate={bool(d.get("escalate"))}, want {e["escalate"]}')
    if not reply:
        return fails, info
    if reply and not text.strip():
        fails.append('reply=true with empty text')
    for p in e.get('must', []):
        if not hit(p, text):
            fails.append(f'must /{p}/')
    for p in e.get('must_not', []):
        if hit(p, text):
            fails.append(f'must_not /{p}/')
    for name, p in GLOBAL.items():
        if name not in e.get('skip_global', []) and hit(p, text):
            fails.append(f'global {name}')
    if english(text):
        fails.append('global english')
    tone = e.get('tone')
    if tone in TONE and not hit(TONE[tone], text):
        fails.append(f'tone {tone}')
    elif tone == 'neutral':
        info.append('tone neutral (informational)')
    return fails, info


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('results')
    ap.add_argument('--fixtures', default=os.path.join(HERE, 'fixtures.jsonl'))
    ap.add_argument('--json', action='store_true', help='print the summary as JSON')
    args = ap.parse_args()
    with open(args.fixtures) as f:
        fixtures = {fx['id']: fx for fx in map(json.loads, filter(str.strip, f))}
    with open(args.results) as f:
        rows = [json.loads(line) for line in f if line.strip()]
    per = collections.defaultdict(lambda: [0, 0])
    total = [0, 0]
    out = []
    for row in sorted(rows, key=lambda r: r['id']):
        fx = fixtures.get(row['id'])
        if fx is None:
            print(f'SKIP {row["id"]}: not in fixtures', file=sys.stderr)
            continue
        fails, info = check(fx, row)
        ok = not fails
        for acc in (per[fx['class']], total):
            acc[0] += ok
            acc[1] += 1
        out.append({'id': row['id'], 'class': fx['class'], 'pass': ok, 'fails': fails, 'info': info})
        if not args.json:
            text = ((row.get('decision') or {}).get('text') or '').replace('\n', ' ')[:110]
            print(f'{"PASS" if ok else "FAIL"} {row["id"]:<24} {"; ".join(fails + info)}' + (f'\n     > {text}' if not ok else ''))
    summary = {'total': {'pass': total[0], 'n': total[1], 'pct': round(100 * total[0] / max(total[1], 1), 1)},
               'classes': {c: {'pass': p, 'n': n, 'pct': round(100 * p / n, 1)} for c, (p, n) in sorted(per.items())},
               'cost_usd': round(sum(r.get('cost_usd') or 0 for r in rows), 4),
               'seconds_mean': round(sum(r.get('seconds') or 0 for r in rows) / max(len(rows), 1), 1)}
    if args.json:
        print(json.dumps({'fixtures': out, 'summary': summary}, ensure_ascii=False, indent=1))
        return
    print('\nclass                 pass/n   %')
    for c, s in summary['classes'].items():
        print(f'{c:<20} {s["pass"]:>3}/{s["n"]:<3} {s["pct"]:>5}')
    t = summary['total']
    print(f'{"TOTAL":<20} {t["pass"]:>3}/{t["n"]:<3} {t["pct"]:>5}   cost ${summary["cost_usd"]}, mean {summary["seconds_mean"]} s/call')


if __name__ == '__main__':
    main()
