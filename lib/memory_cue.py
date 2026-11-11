"""The recall network's cue layer: prompt text to at most 8 concept nodes, rarest first; the only place words live (T1624)."""
import re
import unicodedata

MAX_CUES = 8
STOP = set("a an the of to in on for and or is are be was it its his he him with at by from as that this not no never "
           "only when what which does do how who where than then into out up any all one every each per after before i "
           "should can now you me my we please".split())
# The network's extra stop words (Spanish and English function words); the control arm keeps STOP alone.
STOP_NET = set("el la los las un una unos unas de del al en que se su sus por para es lo le les mi tu este esta eso "
               "como cuando donde muy mas pero ya about if but so just also very too some such there these those they "
               "them their our your were been being have has had will would could might may why both own same again "
               "once".split())


def stem(w):
    """A crude English stem: one plural or verb suffix off a long word."""
    for suf in ("ing", "ed", "es", "s"):
        if len(w) > len(suf) + 3 and w.endswith(suf):
            return w[:-len(suf)]
    return w


def tokens(text):
    """Lower-case stemmed content words of text, accents folded, English and Spanish stop words dropped."""
    plain = "".join(c for c in unicodedata.normalize("NFKD", text.lower()) if not unicodedata.combining(c))
    return [stem(w) for w in re.findall(r"[a-z0-9]+", plain) if w not in STOP and w not in STOP_NET and len(w) > 1]


def cues(text, graph):
    """[(concept node, weight)]: the prompt's words that are concept nodes, the rarest 8 first, each 1/|cues|."""
    found = {"c:" + w for w in tokens(text)} & graph.links.keys()
    top = sorted(found, key=lambda c: (graph.fan(c), c))[:MAX_CUES]
    return [(c, 1.0 / len(top)) for c in top]
