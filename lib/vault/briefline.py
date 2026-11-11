"""A brief's grant lines: `Secrets: <name>[, <name>]` and the T1632 `AI image grant: "<quote>"` (= openrouter, asked = quote)."""
import re

from .registry import NAME

SECRETS = re.compile(r"^[ \t]*(?:[-*][ \t]*)?Secrets:[ \t]*(.*?)[ \t]*$", re.M)
NONE = {"none", "-"}
IMAGE = re.compile(r'^AI image grant: "(.+)"\s*$', re.M)
IMAGE_SECRET = "openrouter"


def parse(text):
    """(names in order, asked words or '', bad tokens) from a brief's text."""
    names, bad = [], []
    for line in SECRETS.findall(text):
        for tok in (t.strip() for t in line.split(",")):
            if not tok or tok.lower() in NONE:
                continue
            if NAME.match(tok):
                names.append(tok)
            else:
                bad.append(tok)
    m = IMAGE.search(text)
    asked = " ".join(m.group(1).split()) if m else ""
    if asked:
        names.append(IMAGE_SECRET)
    return list(dict.fromkeys(names)), asked, bad


def env_name(name):
    """The environment variable that carries a lease on name: FLEET_LEASE_<NAME>."""
    return "FLEET_LEASE_" + name.upper().replace("-", "_")
