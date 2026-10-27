"""The <context> block printed before the inbox: what the bot can do now, its open acks, each channel's recent turns."""
import re

POLL = '3 min'
BUDGET, BOT_MAX, HUMAN_MAX = 8192, 280, 500


def self_line(images_left):
    """Current capabilities, built by code so the model never guesses them from old replies."""
    return (f'You can: see attached images with Read (a GIF/WebP arrives as a numbered contact sheet of up to 12 frames); '
            f'make images (`art` + `post --image`, {images_left} left today); react 👀/✅; escalate to the orchestrator. '
            f'New messages are checked every {POLL}. This line overrides anything you said earlier in <history>.')


def _esc(text):
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


def _cut(text, n):
    return text if len(text) <= n else text[:n - 1] + '…'


class ContextRenderer:
    def __init__(self, me, owner='', budget=BUDGET, bot_max=BOT_MAX, human_max=HUMAN_MAX):
        self.me, self.owner = me, owner
        self.budget, self.bot_max, self.human_max = budget, bot_max, human_max

    def _text(self, m):
        text = m.get('content', '')
        for u in m.get('mentions', []):
            name = '@agents' if u.get('id') == self.me else '@' + (u.get('global_name') or u.get('username') or '?')
            text = text.replace(f'<@{u.get("id")}>', name).replace(f'<@!{u.get("id")}>', name)
        text = re.sub(r'<@&\d+>', '@rol', text)
        files = [a.get('filename', '') for a in m.get('attachments', [])]
        return ' '.join(text.split()) + (f' [adjuntos no cargados: {", ".join(files)}]' if files else '')

    def _acks(self, m):
        return {r['emoji'].get('name') for r in m.get('reactions', []) if r.get('me')}

    def turn(self, m, inbox):
        a = m.get('author', {})
        name, mine = _esc(a.get('global_name') or a.get('username', '?')), a.get('id') == self.me
        ts = m.get('timestamp', '')[11:16]
        if m['id'] in inbox:
            return f'<turn id="{m["id"]}" author="{name}" ts="{ts}" inbox="true"/>'
        who = ' you="true"' if mine else (' owner="true"' if self.owner and a.get('id') == self.owner else '')
        bot = ' bot="true"' if a.get('bot') and not mine else ''
        text = _esc(_cut(self._text(m), self.bot_max if mine else self.human_max))
        return f'<turn author="{name}"{who}{bot} ts="{ts}">{text}</turn>'

    def open_requests(self, channels):
        out = []
        for name, msgs in channels:
            for m in msgs or []:
                acks = self._acks(m)
                if '👀' in acks and '✅' not in acks:
                    a = m.get('author', {})
                    out.append(f'{_esc(name)} {_esc(a.get("global_name") or a.get("username", "?"))} '
                               f'{m.get("timestamp", "")[11:16]}: {_esc(_cut(self._text(m), 120))}')
        return out

    def render(self, channels, inbox_ids, line):
        """channels: [(name, messages oldest first | None)]; the oldest turns go first when over budget."""
        inbox = set(inbox_ids)
        turns = [[self.turn(m, inbox) for m in msgs] if msgs is not None else None for _, msgs in channels]
        opened = self.open_requests(channels)

        def build():
            parts = ['<context kind="data">', f'<self>{line}</self>']
            if opened:
                parts.append('<open>\n' + '\n'.join(opened) + '\n</open>')
            for (name, _), ts in zip(channels, turns):
                if ts is None:
                    parts.append(f'<history channel="{_esc(name)}">historial no disponible</history>')
                else:
                    parts.append(f'<history channel="{_esc(name)}" last="{len(ts)}">\n' + '\n'.join(ts) + '\n</history>')
            parts.append('</context>')
            return '\n'.join(parts)

        out = build()
        while len(out.encode()) > self.budget:
            longest = max((t for t in turns if t), key=len, default=None)
            if not longest:
                break
            longest.pop(0)
            out = build()
        return out
