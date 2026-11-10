"""Agent-caused PO wakes (T1515 P31): `po_count.py add <seat>` counts one in chat's daily counters; no limit (P38)."""
import sys

import chat_dispatch


def add(seat):
    """One more agent-caused wake counted for the seat today."""
    with chat_dispatch.counters() as today:
        today[seat] = today.get(seat, 0) + 1


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "add":
        sys.exit("usage: po_count.py add <seat>")
    add(sys.argv[2])
