"""The re-issue checklist (PLAN T1634 section 9): where to make each credential anew and what follows; names only."""
import tomllib

from . import registry

TOOL_FIELDS = {"place", "reissue", "reissue_then"}


def items(path):
    """[(name, kind, where, then)] for every vault secret, then every tool-owned credential, in registry order."""
    with open(path, "rb") as f:
        data = tomllib.load(f)
    out = []
    for name, row in data.get("secret", {}).items():
        e = registry.entry(name, row)
        out.append((name, f"vault, {e.cls}", e.reissue, row.get("reissue_then", "")))
    for name, row in data.get("tool", {}).items():
        extra = set(row) - TOOL_FIELDS
        if extra or not isinstance(row.get("place"), str) or not registry.NAME.match(name):
            raise registry.RegistryError(f"tool {name}: needs place; fields {', '.join(sorted(TOOL_FIELDS))}")
        link = row.get("reissue", "")
        if link and not link.startswith("https://"):
            raise registry.RegistryError(f"tool {name}: reissue must be an https link")
        out.append((name, f"tool, {row['place']}", link, row.get("reissue_then", "")))
    return out


def checklist(rows):
    """The printable checklist: one numbered line per credential, its link and its next step."""
    lines = []
    for i, (name, kind, where, then) in enumerate(rows, 1):
        lines.append(f"{i}. {name} ({kind})")
        lines.append(f"   new one: {where or '-'}")
        lines.append(f"   then:    {then or '-'}")
    return "\n".join(lines)
