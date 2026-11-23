"""The recall network's cue layer: prompt text to at most 8 concept nodes, rarest first; the only place words live (T1624)."""
import re
import unicodedata

MAX_CUES = 8
SUFFIXES = ("ing", "ed", "es", "or", "s")
STOP = set("a an the of to in on for and or is are be was it its his he him with at by from as that this not no never "
           "only when what which does do how who where than then into out up any all one every each per after before i "
           "should can now you me my we please".split())
# The network's extra stop words (Spanish and English function words); the control arm keeps STOP alone.
STOP_NET = set("el la los las un una unos unas de del al en que se su sus por para es lo le les mi tu este esta eso "
               "como cuando donde muy mas pero ya about if but so just also very too some such there these those they "
               "them their our your were been being have has had will would could might may why both own same again "
               "once".split())
# Contraction stubs and filler of his speech: quoted in many memories, they lit off-topic hints (T1827).
STOP_NET |= set("doesn don didn isn aren wasn weren wouldn couldn shouldn haven hasn hadn ain ll ve re im make makes made "
                "making sense matter matters thing things stuff keep keeps still much many more most like seem seems think "
                "thinking thought know want wanted get gets got go goes going gone really pretty yes yeah ok okay maybe "
                "actually kind lot lots way well even cool nice sure right let lets something anything everything "
                "nothing guess bit little bc because though already else enough here over".split())


def stem(w):
    """A crude English stem: one plural, verb or agent suffix off a long word, then a final e (update, updating: updat)."""
    for suf in SUFFIXES:
        if len(w) > len(suf) + 3 and w.endswith(suf):
            w = w[:-len(suf)]
            break
    return w[:-1] if len(w) > 4 and w.endswith("e") else w


# Full word and its usual short form are one concept (environment, env).
ALIAS = {stem(k): v for k, v in {"environment": "env", "repository": "repo", "configuration": "config", "database": "db",
                                  "directory": "dir", "application": "app", "development": "dev", "production": "prod"}.items()}


def tokens(text):
    """Lower-case stemmed content words (ALIAS short forms), accents folded; stop words and bare numbers dropped."""
    plain = "".join(c for c in unicodedata.normalize("NFKD", text.lower()) if not unicodedata.combining(c))
    return [ALIAS.get(stem(w), stem(w)) for w in re.findall(r"[a-z0-9]+", plain)
            if w not in STOP and w not in STOP_NET and len(w) > 1 and not w.isdigit()]


def variant(a, b):
    """True when two stems are one word in two spellings or languages (art, arte; document, documento)."""
    a, b = sorted((a, b), key=len)
    return a == b or len(a) >= 3 and len(b) - len(a) <= 2 and b.startswith(a)


def cues(text, graph):
    """[(concept node, weight)]: the prompt's words that are concept nodes, the rarest 8 first, each 1/|cues|."""
    found = {"c:" + w for w in tokens(text)} & graph.links.keys()
    top = sorted(found, key=lambda c: (graph.fan(c), c))[:MAX_CUES]
    return [(c, 1.0 / len(top)) for c in top]
