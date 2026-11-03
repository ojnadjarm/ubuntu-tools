"""Project threads (T1481): a job's result goes to a thread mapped to the project it works on, never another project's."""
NOTE_MAX = 200


def homes(threads, projects):
    """Thread ids mapped (threads.json) to any of `projects`."""
    return sorted(t for t, v in threads.items() if v.get('project') in projects)


def misplaced(projects, tid, threads, text, image=''):
    """The project threads a post in `tid` belongs in instead ([] when it may go here): a job working on `projects`
    posts its result in their threads; elsewhere only a one-line note (<= NOTE_MAX chars, no image)."""
    if not projects or (threads.get(tid) or {}).get('project') in projects:
        return []
    note = not image and '\n' not in text.strip() and len(text) <= NOTE_MAX
    return [] if note else homes(threads, projects)
