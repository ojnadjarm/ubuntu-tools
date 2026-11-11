"""Load and validate the vault registry: names, class, delivery modes, hosts; never a value."""
import re
import tomllib
from dataclasses import dataclass

CLASSES = ("free", "ruled", "critical")
MODES = ("proxy", "op", "exchange", "unit")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
HOST = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")
LEGACY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ROW_FIELDS = {"class", "used_in", "modes", "rules", "hosts", "paths", "legacy", "reissue", "max_age_days", "check",
              "cap_usd", "month_cap_usd", "cost", "routes", "methods", "oauth", "scheme"}
METHODS = ("GET", "POST", "PUT", "DELETE")
OAUTH_KEYS = {"client", "token", "authorize"}
CHECK = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
SCHEMES = ("Bearer", "Bot")
ADDED_FIELDS = {"class", "used_in", "rules"}


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
    check: str = ""
    cap_usd: float = 0.0
    month_cap_usd: float = 0.0
    cost: str = ""
    routes: tuple = ()
    methods: tuple = ()
    oauth: dict = None
    scheme: str = "Bearer"


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
    check, cost = row.get("check", ""), row.get("cost", "")
    if check and not (isinstance(check, str) and CHECK.match(check)):
        raise RegistryError(f"{name}: check is a rule name")
    if cost and not (isinstance(cost, str) and re.match(r"^[a-z_]+(\.[a-z_]+)*$", cost)):
        raise RegistryError(f"{name}: cost is a dotted JSON path")
    caps = []
    for k in ("cap_usd", "month_cap_usd"):
        v = row.get(k, 0)
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0:
            raise RegistryError(f"{name}: {k} must be a number of dollars")
        caps.append(float(v))
    routes, methods, oauth = _routes(name, row, hosts), _strs(name, row, "methods"), _oauth(name, row, paths)
    if set(methods) - set(METHODS):
        raise RegistryError(f"{name}: methods must be among {', '.join(METHODS)}")
    scheme = row.get("scheme", "Bearer")
    if scheme not in SCHEMES:
        raise RegistryError(f"{name}: scheme must be one of {', '.join(SCHEMES)}")
    return Entry(name, cls, used_in.strip(), modes, rules, hosts, paths, legacy, reissue, age, added, check, *caps, cost,
                 routes, methods, oauth, scheme)


def _routes(name, row, hosts):
    """{path prefix: host} as sorted pairs; each host one of the pinned hosts."""
    r = row.get("routes", {})
    if not isinstance(r, dict) or any(not (isinstance(p, str) and p.startswith("/")) or h not in hosts
                                      for p, h in r.items()):
        raise RegistryError(f"{name}: routes map a path prefix ('/...') to one of its hosts")
    return tuple(sorted(r.items()))


def _oauth(name, row, paths):
    """The OAuth table (client secret name, token and authorize paths, both allowed paths), or None."""
    o = row.get("oauth")
    if o is None:
        return None
    if not isinstance(o, dict) or set(o) != OAUTH_KEYS or not NAME.match(str(o["client"])) \
            or any(o[k] not in paths for k in ("token", "authorize")):
        raise RegistryError(f"{name}: oauth needs client (a secret name), token and authorize (allowed paths)")
    return dict(o)


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
