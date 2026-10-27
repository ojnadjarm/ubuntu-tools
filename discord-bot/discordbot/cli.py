"""discord-bot status|setup|post|read|invite|selftest|test — operate the forum bot from outside its sandbox."""
import asyncio
import json
import os
import re
import subprocess
import sys
import time

from .config import Config
from .rest import Rest, RestError
from .sanitize import chunks, clean

ME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT_FLAGS = (1 << 18) | (1 << 19)
PERMS = 1024 | 2048 | 64 | 32768 | 65536 | 16 | 128 | (1 << 34) | (1 << 35) | (1 << 38)
FORUM = 15


def unit_state():
    r = subprocess.run(['systemctl', '--user', 'show', 'discord-bot.service', '-p', 'ActiveState',
                        '-p', 'ActiveEnterTimestampMonotonic'], capture_output=True, text=True)
    d = dict(line.split('=', 1) for line in r.stdout.splitlines() if '=' in line)
    up = None
    if d.get('ActiveState') == 'active' and d.get('ActiveEnterTimestampMonotonic', '0') != '0':
        up = time.clock_gettime(time.CLOCK_MONOTONIC) - int(d['ActiveEnterTimestampMonotonic']) / 1e6
    return d.get('ActiveState', 'unknown'), up


async def readiness(rest):
    """Return (guilds, problem) from the API: the exact missing item, or None."""
    app = await rest.call('GET', '/applications/@me')
    guilds = await rest.my_guilds()
    missing = []
    if not guilds:
        missing.append('waiting for invite: bot is in 0 guilds (GET /users/@me/guilds = [])')
    if not app.get('flags', 0) & CONTENT_FLAGS:
        missing.append(f'waiting for intent: Message Content intent off (GET /applications/@me flags={app.get("flags", 0)})')
    return guilds, '; '.join(missing) or None


def write_config(values, path=None):
    path = path or os.environ.get('HARNESS_CONFIG') or os.path.expanduser('~/.config/pc-harness/config.env')
    lines = open(path).read().splitlines() if os.path.exists(path) else []
    for k, v in values.items():
        rx = re.compile(rf'^{k}=')
        new = f'{k}={v}'
        idx = [i for i, ln in enumerate(lines) if rx.match(ln)]
        if idx:
            lines[idx[0]] = new
        else:
            lines.append(new)
    with open(path + '.tmp', 'w') as f:
        f.write('\n'.join(lines) + '\n')
    os.chmod(path + '.tmp', os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600)
    os.replace(path + '.tmp', path)


async def setup(cfg, rest):
    guilds, problem = await readiness(rest)
    if problem:
        print(f'discord-bot: {problem}')
        return 3
    pick = [g for g in guilds if g['id'] == cfg.guild_id] if cfg.guild_id else guilds
    if len(pick) != 1:
        print(f'discord-bot: bot is in {len(guilds)} guilds; set DISCORD_GUILD_ID in config.env')
        return 3
    g = await rest.guild(pick[0]['id'])
    forums = [c for c in await rest.guild_channels(g['id']) if c.get('type') == FORUM]
    forum = next((c for c in forums if c['id'] == cfg.forum_id), forums[0] if forums else None)
    if forum is None:
        print(f'discord-bot: no forum channel in guild "{g["name"]}" (create one, type Forum)')
        return 3
    write_config({'DISCORD_GUILD_ID': g['id'], 'DISCORD_FORUM_ID': forum['id'], 'DISCORD_OWNER_ID': g['owner_id']})
    print(f'discord-bot: guild "{g["name"]}", forum #{forum["name"]}, owner id stored in config.env')
    return 0


async def status(cfg, rest):
    try:
        st = json.load(open(os.path.join(cfg.state_dir, 'status.json')))
    except (OSError, ValueError):
        st = {}
    state, up = unit_state()
    print(f'unit      discord-bot.service {state}' + (f', uptime {int(up // 3600)}h{int(up % 3600 // 60):02d}m' if up else ''))
    guilds, problem = await readiness(rest)
    print(f'api       {len(guilds)} guild(s)' + (f'; {problem}' if problem else '; intent on'))
    g, f = st.get('guild') or {}, st.get('forum') or {}
    print(f'guild     {g.get("name", "-")}')
    print(f'forum     #{f.get("name", "-")}')
    print(f'tags      {", ".join(st.get("tags", [])) or "-"}')
    if st.get('connected_at'):
        print(f'gateway   connected {time.strftime("%Y-%m-%d %H:%M", time.localtime(st["connected_at"]))}')
    if st.get('problem'):
        print(f'problem   {st["problem"]}')
    return 0


async def post(cfg, rest, args):
    if args[:1] == ['--new'] and len(args) >= 3:
        res = await rest.create_post(cfg.forum_id, args[1][:100], clean(' '.join(args[2:]))[:1900], [])
        print(f'posted thread {res["id"]}')
        return 0
    if len(args) < 2:
        print('usage: discord-bot post <thread-id> <text…> | post --new <title> <text…>')
        return 2
    for part in chunks(clean(' '.join(args[1:]))):
        await rest.send(args[0], part)
    print('posted')
    return 0


async def read(cfg, rest, args):
    if args:
        for m in reversed(await rest.messages(args[0], 20)):
            print(f'{m["author"].get("username", "?")}: {m.get("content", "")}')
        return 0
    act = await rest.call('GET', f'/guilds/{cfg.guild_id}/threads/active')
    for t in act.get('threads', []):
        if t.get('parent_id') == cfg.forum_id:
            print(f'{t["id"]}  {t["name"]}  tags={len(t.get("applied_tags", []))}  msgs={t.get("message_count", 0)}')
    return 0


async def amain(argv):
    cmd, args = (argv[0] if argv else 'status'), argv[1:]
    if cmd == 'selftest':
        return subprocess.call([os.path.join(ME, 'bin', 'sandbox'), '--selftest'])
    if cmd == 'test':
        return subprocess.call([sys.executable, '-m', 'unittest', 'discover', '-s', os.path.join(ME, 'tests'), '-t', ME],
                               cwd=ME)
    cfg = Config.from_env()
    rest = Rest(cfg.api_base, cfg.token())
    try:
        if cmd == 'invite':
            app = (await rest.call('GET', '/applications/@me'))['id']
            print(f'https://discord.com/oauth2/authorize?client_id={app}&scope=bot&permissions={PERMS}')
            return 0
        fn = {'status': status, 'setup': setup}.get(cmd)
        if fn:
            return await fn(cfg, rest)
        if cmd in ('post', 'read'):
            return await {'post': post, 'read': read}[cmd](cfg, rest, args)
        print(__doc__)
        return 2
    except RestError as e:
        print(f'discord-bot: Discord API error {e.status}')
        return 1
    finally:
        await rest.close()


def main():
    sys.exit(asyncio.run(amain(sys.argv[1:])))


if __name__ == '__main__':
    main()
