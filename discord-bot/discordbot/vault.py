"""Discord REST through the fleet vault (T1634-V8): a lease in the URL, the broker adds the token; no value here."""
import json
import os
import socket
import sys
import time
from urllib.parse import urlsplit

from .rest import Rest, RestError

SECRET = 'discord-bot-token'
LEASE_ENV = 'FLEET_LEASE_DISCORD_BOT_TOKEN'
SOCKET = '/run/fleet-vault/admin.sock'


class NoLease(RestError):
    """The broker gave no lease; the message says why (never a lease id)."""

    def __init__(self, why):
        super().__init__(403, {'message': why})
        self.why = why


def ask(path, req, timeout=10):
    """One JSON-line request to the broker's admin socket; the reply object."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(path)
        with s.makefile('rwb') as f:
            f.write(json.dumps(req).encode() + b'\n')
            f.flush()
            return json.loads(f.readline() or b'{}')


class LeaseSource:
    """The Discord lease: the launcher's (FLEET_LEASE_DISCORD_BOT_TOKEN), else a grant of our own, renewed before it ends."""

    def __init__(self, env, ticket, ttl=3600, margin=300, clock=time.time, ask=ask):
        self.given, self.ticket, self.ttl, self.margin = env.get(LEASE_ENV, ''), ticket, ttl, margin
        self.socket = env.get('FLEET_VAULT_SOCKET') or SOCKET
        self.vault = (env.get('FLEET_VAULT_URL') or f'http://127.0.0.1:{env.get("FLEET_VAULT_PORT") or 18480}').rstrip('/')
        self.clock, self.ask = clock, ask
        self._id, self._exp = '', 0.0

    def _grant(self, ticket, ttl):
        try:
            r = self.ask(self.socket, {'op': 'grant', 'name': SECRET, 'ticket': ticket, 'agent': self.ticket, 'ttl': ttl})
        except (OSError, ValueError) as e:
            r = {'error': f'vault unreachable ({type(e).__name__})'}
        if not r.get('ok'):
            why = r.get('error') or 'refused'
            print(f'discord: no vault lease for {SECRET}: {why}', file=sys.stderr)
            raise NoLease(why)
        return r['lease'], float(r['expires'])

    def lease(self):
        """The lease id to call with now."""
        if self.given:
            return self.given
        if not self._id or self._exp - self.clock() <= self.margin:
            self._id, self._exp = self._grant(self.ticket, self.ttl)
        return self._id

    def base(self, api_base):
        """The broker URL that stands for api_base."""
        return f'{self.vault}/{self.lease()}/{SECRET}{urlsplit(api_base).path}'

    def mint(self, ticket, ttl):
        """A separate lease for a worker this process launches; None when refused."""
        try:
            return self._grant(ticket, ttl)[0]
        except NoLease:
            return None

    def revoke(self, lid):
        """Drop a lease minted for a worker."""
        try:
            self.ask(self.socket, {'op': 'revoke', 'lease': lid, 'ticket': self.ticket, 'agent': self.ticket})
        except (OSError, ValueError):
            pass


def make_rest(cfg, env, ticket):
    """Rest with the token file while one is set or still present, else through the vault with a lease."""
    if cfg.token_file and os.path.exists(cfg.token_file):
        return Rest(cfg.api_base, cfg.token(), cfg.proxy)
    return Rest(cfg.api_base, None, lease=LeaseSource(env, ticket))
