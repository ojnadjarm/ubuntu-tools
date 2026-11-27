"""Gates: named limits on the harness's measures (defaults: RULES.md rule 14)."""
import operator

DEFAULT_GATES = {
    "excess": ["<=", 0.015],
    "excess_1s": ["<=", 0.025],
    "pop_still": ["<=", 0.010],
    "tile": ["<=", 0.10],
    "encode_added": ["<=", 0.025],
    "subframe": ["<=", 0.2],
    "purity": ["==", True],
    "edge_px": [">=", 8.0],
    "empty_tiles": ["<=", 10.0],
    "palette_dist": ["<=", 2.5],
    "warm": ["<=", 12.0],
    "cool": [">=", 20.0],
    "top3_value": [">=", 85.0],
}
OPS = {"<=": operator.le, ">=": operator.ge, "==": operator.eq}


def gate(report: dict, gates: dict) -> list:
    """Names of the gates whose measure is in the report and fails; measures not in the report are skipped."""
    return [k for k, (op, v) in gates.items() if report.get(k) is not None and not OPS[op](report[k], v)]
