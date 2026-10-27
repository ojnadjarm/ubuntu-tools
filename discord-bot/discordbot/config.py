"""DISCORD_* settings read from the environment (config.env keys, passed into the sandbox by bin/serve)."""
import os
from dataclasses import dataclass, field

STATUS_TAGS = ('new', 'accepted', 'in progress', 'done')
APPROVED_TAG = 'approved'
APPROVE_EMOJI = '✅'


def _ids(raw):
    return frozenset(x for x in raw.replace(',', ' ').split() if x.isdigit())


@dataclass
class Config:
    token_file: str
    state_dir: str
    api_base: str = 'https://discord.com/api/v10'
    proxy: str = ''
    guild_id: str = ''
    forum_id: str = ''
    owner_id: str = ''
    allowlist: frozenset = field(default_factory=frozenset)
    requests_per_day: int = 10
    jobs_per_day: int = 3
    poll_seconds: float = 2.0
    forum_replies: str = 'bot'

    @classmethod
    def from_env(cls, env=None):
        e = os.environ if env is None else env
        home = e.get('HOME', '')
        return cls(
            token_file=e.get('DISCORD_TOKEN_FILE', f'{home}/agents/secrets/discord-bot-token'),
            state_dir=e.get('DISCORD_STATE_DIR', f'{home}/agents/discord-bot/state'),
            api_base=e.get('DISCORD_API_BASE', cls.api_base),
            proxy=e.get('DISCORD_PROXY', ''),
            guild_id=e.get('DISCORD_GUILD_ID', ''),
            forum_id=e.get('DISCORD_FORUM_ID', ''),
            owner_id=e.get('DISCORD_OWNER_ID', ''),
            allowlist=_ids(e.get('DISCORD_ALLOWLIST', '')),
            requests_per_day=int(e.get('DISCORD_REQUESTS_PER_DAY', '10')),
            jobs_per_day=int(e.get('DISCORD_JOBS_PER_DAY', '3')),
            poll_seconds=float(e.get('DISCORD_POLL_SECONDS', '2')),
            forum_replies=e.get('DISCORD_FORUM_REPLIES', 'bot'),
        )

    def token(self):
        with open(self.token_file) as f:
            return f.read().strip()
