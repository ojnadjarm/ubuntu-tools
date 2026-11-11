"""Load and validate the vault registry: names, class, delivery modes, hosts; never a value."""
import re
import tomllib
from dataclasses import dataclass

CLASSES = ("free", "ruled", "critical")
MODES = ("proxy", "op", "exchange", "unit")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
HOST = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")
LEGACY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ROW_FIELDS = {"class", "used_in", "modes", "rules", "hosts", "paths", "legacy", "reissue", "max_age_days"}
ADDED_FIELDS = {"class", "used_in"}


class RegistryError(ValueError):
    """A registry row that breaks a rule."""


@dataclass(frozen=True)
class Entry:
    """One secret's description; `added` marks a row the owner added by hand, not a registry row."""
    name: str
    cls: str
    used_in: str
    modes: tuple = ()
    rules: str = ""
    hosts: tuple = ()
    paths: tuple = ()
    legacy: str = ""
    reissue: str = ""
    max_age_days: int = 0
    added: bool = False


def _strs(name, row, key):
    v = row.get(key, [])
    if not isinstance(v, list) or not all(isinstance(x, str) and x for x in v):
        raise RegistryError(f"{name}: {key} must be a list of strings")
    return tuple(v)


def entry(name, row, added=False):
    """Validate one row and return its Entry."""
    if not isinstance(name, str) or not NAME.match(name):
        raise RegistryError(f"bad name {name!r}: lowercase letters, digits, '-'")
    allowed = ADDED_FIELDS if added else ROW_FIELDS
    extra = set(row) - allowed
    if extra:
        raise RegistryError(f"{name}: unknown field(s) {', '.join(sorted(extra))}")
    cls, used_in = row.get("class"), row.get("used_in")
    if cls not in CLASSES:
        raise RegistryError(f"{name}: class must be one of {', '.join(CLASSES)}")
    if not isinstance(used_in, str) or not used_in.strip() or len(used_in) > 200:
        raise RegistryError(f"{name}: used_in is required (one line, at most 200 characters)")
    modes, hosts, paths = _strs(name, row, "modes"), _strs(name, row, "hosts"), _strs(name, row, "paths")
    if set(modes) - set(MODES):
        raise RegistryError(f"{name}: modes must be among {', '.join(MODES)}")
    if any(not HOST.match(h) for h in hosts):
        raise RegistryError(f"{name}: hosts must be plain host names")
    if any(not p.startswith("/") for p in paths):
        raise RegistryError(f"{name}: paths must start with '/'")
    if {"proxy", "exchange"} & set(modes) and not hosts:
        raise RegistryError(f"{name}: proxy and exchange modes need pinned hosts")
    rules = row.get("rules", "")
    if cls == "ruled" and not (isinstance(rules, str) and rules.strip()):
        raise RegistryError(f"{name}: class ruled needs its rules")
    legacy = row.get("legacy", "")
    if legacy and not LEGACY.match(legacy):
        raise RegistryError(f"{name}: legacy is a file name under the secrets dir")
    reissue = row.get("reissue", "")
    if reissue and not reissue.startswith("https://"):
        raise RegistryError(f"{name}: reissue must be an https link")
    age = row.get("max_age_days", 0)
    if not isinstance(age, int) or age < 0:
        raise RegistryError(f"{name}: max_age_days must be a whole number of days")
    return Entry(name, cls, used_in.strip(), modes, rules, hosts, paths, legacy, reissue, age, added)


def load(path, added=None):
    """Read the registry file and merge the owner-added rows: {name: Entry}."""
    with open(path, "rb") as f:
        data = tomllib.load(f)
    extra = set(data) - {"secret"}
    if extra:
        raise RegistryError(f"unknown table(s) {', '.join(sorted(extra))}")
    out = {n: entry(n, row) for n, row in data.get("secret", {}).items()}
    for n, row in (added or {}).items():
        if n in out:
            raise RegistryError(f"{n}: added by hand and also a registry row")
        out[n] = entry(n, row, added=True)
    return out
