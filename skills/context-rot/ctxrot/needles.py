"""Seeded generator of 8 planted facts, their questions and gold answers, plus one join question.

Hard mode (updates >= 1) adds, per fact, superseded earlier values and a near-miss twin entity, so recall needs the
latest value of the exact entity (the way an orchestrator must track changed decisions).
"""
import random
from dataclasses import dataclass, field

CODENAMES = ["Kestrel", "Juniper", "Basalt", "Marigold", "Tamarack", "Osprey", "Quillon", "Saffron", "Vervain",
             "Halcyon", "Tourmaline", "Larkspur", "Wolfram", "Peregrine", "Cobalt", "Thistle", "Merlin", "Sorrel"]
PEOPLE = ["Ines Varga", "Tomas Okonkwo", "Lena Moreau", "Ravi Castell", "Dora Lindqvist", "Hugo Brennecke",
          "Maya Ferrer", "Otto Kowal", "Nadia Sorensen", "Felix Duarte"]
ROOMS = ["Aster", "Birch", "Cypress", "Dunlin", "Egret", "Fennel", "Garnet", "Heath"]
SERVICES = ["ledger-sync", "thumb-render", "quiz-grader", "mail-relay", "badge-issuer", "grade-export"]

# kind: (value generator, statement, question); {n} = entity, {v} = value
KINDS = {
    "port": (lambda r: str(r.randint(20000, 29999)), "The {n} dashboard listens on port {v}.",
             "Which port does the {n} dashboard listen on?"),
    "ttl": (lambda r: str(r.randint(301, 899)), "Owner decision: the cache TTL for {n} is {v} seconds.",
            "What cache TTL (seconds) is set for {n}?"),
    "retries": (lambda r: str(r.randint(11, 19)), "The {n} importer gives up after {v} retries.",
                "After how many retries does the {n} importer give up?"),
    "time": (lambda r: f"{r.randint(0, 23):02d}:{r.choice([7, 13, 22, 37, 44, 52]):02d}",
             "The {n} nightly job starts at {v} UTC.", "At what time (UTC) does the {n} nightly job start?"),
    "key": (lambda r: "".join(r.choice("0123456789abcdef") for _ in range(6)),
            "Build {n} was signed with key fingerprint {v}.", "What key fingerprint signed build {n}?"),
    "oncall": (lambda r: r.choice(PEOPLE), "The on-call contact for {n} this week is {v}.",
               "Who is the on-call contact for {n} this week?"),
}
CORRECTION = "Correction, replaces any earlier value: "


@dataclass
class Fact:
    key: str
    text: str
    question: str
    answer: str
    distractors: list = field(default_factory=list)


def _other(rng, gen, avoid):
    v = gen(rng)
    while v in avoid:
        v = gen(rng)
    return v


def _harden(rng, fact: Fact, statement, gen, name, updates: int) -> None:
    """Prefix the current value as a correction; add superseded values (later ones also as corrections) and a twin."""
    old = _other(rng, gen, {fact.answer})
    fact.distractors = [("before", statement.format(n=name, v=old)),
                        ("any", statement.format(n=f"{name}-legacy", v=_other(rng, gen, {fact.answer, old})))]
    seen, v = {fact.answer, old}, old
    for i in range(updates - 1):
        v = _other(rng, gen, seen if i < 7 else {fact.answer, v})  # past stress8 values may repeat (small ranges)
        seen.add(v)
        fact.distractors.append(("before", CORRECTION + statement.format(n=name, v=v)))
    fact.text = CORRECTION + fact.text


def generate(seed: int, updates: int = 0):
    """Return (facts, join_question, join_answer, join_keys); updates = superseded values per fact (0 = plain)."""
    hard = updates > 0
    rng = random.Random(seed)
    names = rng.sample(CODENAMES, 8)
    facts = []
    for (key, (gen, st, q)), name in zip(KINDS.items(), names):
        v = gen(rng)
        f = Fact(key, st.format(n=name, v=v), q.format(n=name), v)
        if hard:
            _harden(rng, f, st, gen, name, updates)
        facts.append(f)
    svc, room, unit = rng.choice(SERVICES), rng.choice(ROOMS), rng.randint(21, 39)
    host_gen = lambda r: f"{names[6].lower()}-{r.randint(2, 9)}"  # noqa: E731
    host = host_gen(rng)
    ja = Fact("join_a", f"For ticket {names[7]}, the {svc} service runs on host {host}.",
              f"Which host runs the {svc} service for ticket {names[7]}?", host)
    jb = Fact("join_b", f"Host {host} is racked in unit U{unit} of server room {room}.",
              f"Which host is racked in unit U{unit}?", host)
    if hard:
        old_host = _other(rng, host_gen, {host})
        ja.distractors = [("before", f"For ticket {names[7]}, the {svc} service runs on host {old_host}.")]
        ja.text = CORRECTION + ja.text
        jb.distractors = [("any", f"Host {old_host} is racked in unit U{unit + 1} of server room "
                                  f"{_other(rng, lambda r: r.choice(ROOMS), {room})}.")]
    facts += [ja, jb]
    rng.shuffle(facts)
    while abs([f.key for f in facts].index("join_a") - [f.key for f in facts].index("join_b")) < 3:
        rng.shuffle(facts)
    join_q = f"In which server room does the {svc} service for ticket {names[7]} physically run now? (one word)"
    return facts, join_q, room, ("join_a", "join_b")
