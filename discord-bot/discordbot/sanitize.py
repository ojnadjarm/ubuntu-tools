"""Strip machine values and secret-shaped strings from text the bot posts."""
import re

_PATTERNS = [
    (re.compile(r'(?:/home|/root|/Users)/[^\s`\'")\]]*'), '<path>'),
    (re.compile(r'~/[^\s`\'")\]]*'), '<path>'),
    (re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '<ip>'),
    (re.compile(r'\b(?:(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4}|(?:[0-9a-f]{1,4}:){1,6}:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})\b',
                re.I), '<ip>'),
    (re.compile(r'\b[\w.-]+\.ts\.net\b', re.I), '<host>'),
    (re.compile(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<email>'),
    (re.compile(r'\b[MN][A-Za-z\d_-]{23,27}\.[\w-]{6}\.[\w-]{27,40}\b'), '<secret>'),
    (re.compile(r'\b(?:sk-ant-|sk-|ghp_|gho_|xox[abp]-)[\w-]{10,}'), '<secret>'),
]


def clean(text, extra=()):
    """Return text with paths, IPs, hosts, emails, tokens and any `extra` literal values replaced."""
    for v in sorted((v for v in extra if v and len(v) >= 4), key=len, reverse=True):
        text = text.replace(v, '<redacted>')
    for rx, sub in _PATTERNS:
        text = rx.sub(sub, text)
    return text


def chunks(text, size=1900):
    """Split text into Discord-sized messages on line breaks where possible."""
    out = []
    while len(text) > size:
        cut = text.rfind('\n', 0, size)
        cut = cut if cut > size // 2 else size
        out.append(text[:cut])
        text = text[cut:].lstrip('\n')
    return out + ([text] if text else [])
