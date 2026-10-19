"""Who approved: the guild audit log is the only record of which user applied a forum tag."""
THREAD_UPDATE = 111


async def tag_added_by(rest, guild_id, thread_id, tag_id):
    """User id of the newest audit-log entry that added tag_id to the thread, or ''."""
    log = await rest.audit_log(guild_id, THREAD_UPDATE)
    for e in log.get('audit_log_entries', []):
        if e.get('target_id') != thread_id:
            continue
        for c in e.get('changes', []):
            if (c.get('key') == 'applied_tags' and tag_id in (c.get('new_value') or [])
                    and tag_id not in (c.get('old_value') or [])):
                return e.get('user_id') or ''
    return ''
