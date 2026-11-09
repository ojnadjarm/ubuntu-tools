"""Secret patterns and redaction: the one source for the audit hook and the chat guard; re loads on first use."""


# Substrings without which no redaction pattern can match: lower-cased, then case-sensitive.
TRIGGERS = ('token', 'topic', 'pass', 'secret', 'key', 'authorization', 'bearer', 'mysql', 'mariadb', 'curl')
CASED = ('sk-', 'sk_', 'ghp', 'gho', 'ghu', 'ghs', 'github_pat', 'xoxb', 'xoxp', 'AKIA', 'eyJ')
HEX = str.maketrans(dict.fromkeys('0123456789abcdefABCDEF', 'h'))
_RX = None


def may_hold_secret(s):
    """False only when no redaction pattern can match s."""
    if not s.isascii():
        return True
    low = s.lower()
    return (any(t in low for t in TRIGGERS) or any(t in s for t in CASED)
            or ('@' in s and '://' in s) or 'h' * 40 in s.translate(HEX))


def patterns():
    """The compiled redaction patterns (SECRET, URLCRED, KEYLIKE, HEXKEY), compiled on first use."""
    global _RX
    if _RX is None:
        import re
        _RX = (re.compile(
    r'((?:token|topic|passwd|password|(?-i:(?<![A-Za-z])PASS)|secret|(?:secret|private)[\w-]*key|api[-_]?key|apikey'
    r'|authorization|\bx-[\w-]*key)["\']?\s*[:=]\s*|bearer\s+'
    r'|--(?:[\w-]*-)?(?:token|api-key|secret|pass(?:wd|word)?)[= ]|\b(?:mysql\w*|mariadb\w*)\b[^|;&\n]*?\s(?-i:-p)(?=\S)'
    r'|\bsshpass\b[^|;&\n]*?\s(?-i:-p)\s*|\bcurl\b[^|;&\n]*?\s(?:(?-i:-u)\s*|--user[= ])[^\s:"\']+:)'
    r'(["\'])?((?:bearer\s+)?)(?(2)(?:(?!\2)[^\n])+|[^\s"\'&;]+)', re.I),
               re.compile(r'(\b[a-z][\w+.-]*://[^\s:/@"\']+:)[^\s@/"\']+(?=@)', re.I),
               re.compile(r'\b(?:(?:sk|ghp|gho|ghu|ghs|github_pat|xoxb|xoxp)[-_][A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}\b'
                          r'|eyJ[\w-]{10,}\.[\w-]{2,}\.[\w-]*)'),
               re.compile(r'(?<!sha256)([=:]\s*["\']?)[0-9a-fA-F]{40,}\b'))
    return _RX


def redact(s):
    if not may_hold_secret(s):
        return s
    SECRET, URLCRED, KEYLIKE, HEXKEY = patterns()
    s = SECRET.sub(lambda m: m.group(1) + (m.group(2) or '') + m.group(3) + '<redacted>', s)
    s = URLCRED.sub(lambda m: m.group(1) + '<redacted>', s)
    s = HEXKEY.sub(lambda m: m.group(1) + '<redacted>', s)
    return KEYLIKE.sub('<redacted>', s)


def redact_values(v):
    """Redact every string inside a nested dict/list before it is JSON-escaped."""
    if isinstance(v, str):
        return redact(v)
    if isinstance(v, dict):
        return {k: redact_values(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [redact_values(x) for x in v]
    return v
