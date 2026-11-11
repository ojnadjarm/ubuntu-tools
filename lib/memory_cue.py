"""The recall network's cue layer: prompt text to at most 8 concept nodes, rarest first; the only place words live (T1624)."""
import re

MAX_CUES = 8
STOP = set("a an the of to in on for and or is are be was it its his he him with at by from as that this not no never "
           "only when what which does do how who where than then into out up any all one every each per after before i "
           "should can now you me my we please".split())


def stem(w):
    """A crude English stem: one plural or verb suffix off a long word."""
    for suf in ("ing", "ed", "es", "s"):
        if len(w) > len(suf) + 3 and w.endswith(suf):
            return w[:-len(suf)]
    return w


def tokens(text):
    """Lower-case stemmed content words of text, stop words dropped."""
    return [stem(w) for w in re.findall(r"[a-z0-9]+", text.lower()) if w not in STOP and len(w) > 1]


def cues(text, graph):
    """[(concept node, weight)]: the prompt's words that are concept nodes, the rarest 8 first, each 1/|cues|."""
    found = {"c:" + w for w in tokens(text)} & graph.links.keys()
    top = sorted(found, key=lambda c: (graph.fan(c), c))[:MAX_CUES]
    return [(c, 1.0 / len(top)) for c in top]
