"""FILE-CLAIMS.md rows for findings: claim, unclaim, and who else holds a path."""
import os
import re

from .common import AGENTS, CLAIMS, DATE, absp, die, locked, rel


def claims_rows():
    try:
        return [l.rstrip('\n') for l in open(CLAIMS) if l.startswith('- ')]
    except OSError:
        return []


def claim_path(p):
    """A board path as absolute: ~/x and /x as given, anything else relative to ~/agents."""
    p = p.split(' (')[0].strip().rstrip('*').rstrip('/')
    if not p:
        return ''
    if p.startswith('~') or p.startswith('/'):
        return absp(p)
    return os.path.abspath(os.path.join(AGENTS, p))


def claimed_by_others(me):
    out = []
    for row in claims_rows():
        cells = [c.strip() for c in row[2:].split('·')]
        if len(cells) < 2 or cells[0] == me:
            continue
        for p in re.split(r',\s*', cells[1]):
            p = claim_path(p)
            if p:
                out.append((cells[0], p))
    return out


def covers(claim, t):
    """A claim on x covers x, everything under x/, and x.<ext> (a row may name a file without its extension)."""
    return t == claim or t.startswith(claim + '/') or claim.startswith(t + '/') or \
        (t.startswith(claim + '.') and '/' not in t[len(claim):])


def cmd_claim(a):
    who = f'code-review-{a.id}'
    targets = [absp(p) for p in a.paths]

    def check_and_add():
        for owner, p in claimed_by_others(who):
            for t in targets:
                if covers(p, t):
                    return f'{rel(t)} is claimed by {owner}'
        with open(CLAIMS, 'a') as fh:
            fh.write(f'- {who} · {", ".join("~/" + rel(t) for t in targets)} · {DATE}\n')
        return ''
    why = locked(CLAIMS, check_and_add)
    if why:
        die(why, 3)
    print(f'claimed {len(targets)} path(s) as {who}')


def drop_rows(match):
    """Remove matching rows; re-read before the write so a row added meanwhile (e.g. by the Edit tool) survives."""
    def drop():
        for _ in range(5):
            try:
                text = open(CLAIMS).read()
            except OSError:
                return 0
            lines = text.splitlines(keepends=True)
            keep = [l for l in lines if not match(l)]
            tmp = CLAIMS + '.cr-tmp'
            with open(tmp, 'w') as fh:
                fh.writelines(keep)
            if open(CLAIMS).read() == text:
                os.replace(tmp, CLAIMS)
                return len(lines) - len(keep)
        os.unlink(tmp)
        return 0
    return locked(CLAIMS, drop)


def cmd_unclaim(a):
    who = f'code-review-{a.id}'
    print(f'unclaimed {drop_rows(lambda l: l.startswith(f"- {who} ·"))} row(s)')
