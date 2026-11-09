"""Chat guard: check(text, seat, ch, to, names) allows a message or holds it with the rule's name; any error holds it."""
import functools
import os
import re
import subprocess
import sys

import chat_route
import org
import redact

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'bin')
sys.path.insert(0, BIN)
import protectedlib  # noqa: E402

TICKET = re.compile(r'(?<![A-Za-z0-9])[A-Z]{2,}-\d+(?![0-9])')


def config_path():
    """The machine config file (HARNESS_CONFIG, else ~/.config/pc-harness/config.env)."""
    return os.environ.get('HARNESS_CONFIG', os.path.expanduser('~/.config/pc-harness/config.env'))


def config_mtime():
    """The config file's mtime, so cached reads refresh when it changes; 0 when it is missing."""
    try:
        return os.stat(config_path()).st_mtime
    except OSError:
        return 0


@functools.lru_cache(maxsize=2)
def protected_paths(_mtime):
    """Absolute paths of every protected project (`protected entries path`)."""
    out = subprocess.run([os.path.join(BIN, 'protected'), 'entries', 'path'], capture_output=True, text=True,
                         check=True, timeout=10).stdout
    return tuple(p.rstrip('/') for p in out.splitlines() if p.strip())


@functools.lru_cache(maxsize=2)
def protected_words(_mtime):
    """[(project, ERE)] of every protected project's text words (`protected eres text`, lowercase)."""
    return tuple(protectedlib.eres('text'))


@functools.lru_cache(maxsize=2)
def deny_words(_mtime):
    """CHAT_DENY_WORDS, space-separated, from the environment or else the config file, lower-cased."""
    val = os.environ.get('CHAT_DENY_WORDS')
    if val is None:
        val = ''
        try:
            with open(config_path()) as f:
                for l in f:
                    if re.match(r'\s*(export\s+)?CHAT_DENY_WORDS=', l):
                        val = re.split(r'\s+#', l.split('=', 1)[1])[0].strip().strip('"\'')
        except OSError:
            pass
    return tuple(w.lower() for w in val.split())


def has_secret(text, seat):
    """A token, password or key in any shape the audit redaction knows."""
    return redact.redact(text) != text


def has_protected_path(text, seat):
    """A protected project's path, absolute or written from ~ or $HOME."""
    home = os.path.expanduser('~')
    text = re.sub(r'(?<![\w/.-])(?:~|\$HOME|\$\{HOME\})(?=/|$)', home, text)
    return any(re.search(re.escape(p) + r'(?![\w.-])', text) for p in protected_paths(config_mtime()))


def has_deny_word(text, seat):
    """A CHAT_DENY_WORDS word (client names, finance, genealogy), any case."""
    low = text.lower()
    return any(re.search(r'(?<![a-z0-9])' + re.escape(w) + r'(?![a-z0-9])', low) for w in deny_words(config_mtime()))


def has_ticket_key(text, seat):
    """A tracker key such as AB-123."""
    return bool(TICKET.search(text))


def has_protected_word(text, seat):
    """A protected project's word (`protected` text matcher), any case."""
    return protectedlib.project(protected_words(config_mtime()), text.lower()) is not None


RULES = (('secret', has_secret), ('protected path', has_protected_path), ('deny word', has_deny_word))
STRICT = (('ticket key', has_ticket_key), ('protected word', has_protected_word))


def strict(text, seat, ch, to):
    """True when a pull seat (outside the fleet, e.g. a protected project's own session) sends, receives or is named."""
    parties = {seat, *(to or ())} | set(chat_route.MENTION.findall(text.lower()))
    if ch and ch.startswith('dm-'):
        parties |= set(ch[3:].split('--'))
    return any(s['wake'] == 'pull' and s['id'] in parties for s in org.seats())


def check(text, seat, ch=None, to=(), names=()):
    """(True, '') to allow text from seat in ch to `to`, else (False, the rule that holds it); never names the matched
    text. A message to, from or naming a pull seat also meets the STRICT rules and carries no attachment. Attachment
    names meet the same rules as the text; their content is not scanned."""
    try:
        if not isinstance(text, str) or not all(isinstance(n, str) for n in names):
            return False, 'not text'
        tight = strict(text, seat, ch, to)
        if names and tight:
            return False, 'attachment'
        rules = RULES + STRICT if tight else RULES
        for name, rule in rules:
            if any(rule(t, seat) for t in (text, *names)):
                return False, name
        return True, ''
    except Exception as e:
        return False, 'guard error: ' + type(e).__name__
