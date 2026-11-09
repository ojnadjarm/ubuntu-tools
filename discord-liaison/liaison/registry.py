"""Project registry (projects.json): which repo a forum thread belongs to and who handles its work."""
import json


class Registry:
    def __init__(self, path):
        with open(path) as f:
            data = json.load(f)
        self.projects = {p['id']: p for p in data['projects']}
        self.router = data.get('router')

    def get(self, pid):
        return self.projects.get(pid)

    def match(self, title, tag_names):
        """First project whose tag is on the thread, else whose title keyword is in the thread title."""
        tags, low = {t.lower() for t in tag_names}, title.lower()
        for key in ('tags', 'title'):
            for p in self.projects.values():
                words = [w.lower() for w in p.get('match', {}).get(key, [])]
                if any(w in tags for w in words) if key == 'tags' else any(w in low for w in words):
                    return p
        return None

    def route(self, pid):
        """'liaison' when the liaison does the work itself, the PO agent's name when the entry has `po`, None if unknown."""
        p = self.get(pid)
        return None if p is None else (p.get('po') or 'liaison')

    def named(self, text):
        """Ids of the projects whose tag or title keyword appears in the text."""
        low = text.lower()
        return {p['id'] for p in self.projects.values()
                if any(w.lower() in low for k in ('tags', 'title') for w in p.get('match', {}).get(k, []))}

    def dispatch(self, m, pid):
        """Who gets a message by code: its project's PO, the router (no project, or another project named), else None."""
        if m.get('channel') == 'general':
            return None
        route = self.route(pid) if pid else None
        if self.router and (route is None or self.named(m['content']) - {pid}):
            return self.router
        return route if route not in (None, 'liaison') else None
