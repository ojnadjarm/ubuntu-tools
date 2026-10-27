"""Conversations (T1421): a forum thread, or one author in #general; the newest message of each is the one that counts."""
from .watch import addressed


def key(m):
    """The conversation a message belongs to."""
    return f'{m["thread_id"]}:{m.get("author_id", "")}' if m.get('channel') == 'general' else m['thread_id']


def merge(*lists):
    """Messages deduped by id, oldest first."""
    seen = {}
    for msgs in lists:
        for m in msgs:
            seen.setdefault(m['id'], m)
    return sorted(seen.values(), key=lambda m: int(m['id']))


def batch(msgs):
    """[[message…]] per conversation, oldest -> newest, conversations ordered by their newest message."""
    groups = {}
    for m in merge(msgs):
        groups.setdefault(key(m), []).append(m)
    return sorted(groups.values(), key=lambda g: int(g[-1]['id']))


def newer(raw, after, authors, general=False, me='', role=''):
    """The first raw Discord message after id `after` written by one of `authors` (addressed to the bot in #general)."""
    for m in sorted(raw, key=lambda m: int(m['id'])):
        if int(m['id']) > int(after) and m.get('author', {}).get('id') in authors and (
                not general or addressed(m, me, role)):
            return m
    return None
