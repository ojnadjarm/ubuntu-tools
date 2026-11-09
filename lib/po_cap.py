"""Agent-caused PO wakes (T1515 P31): `po_cap.py take <seat>` counts one in chat's daily counters; exit 4 at the cap (12)."""
import sys

import chat_dispatch
import chat_route


def take(seat, cap=chat_route.CAP):
    """True and one more wake counted for the seat today, or False when it already had `cap`."""
    with chat_dispatch.counters() as today:
        if today.get(seat, 0) >= cap:
            return False
        today[seat] = today.get(seat, 0) + 1
    return True


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "take":
        sys.exit("usage: po_cap.py take <seat>")
    sys.exit(0 if take(sys.argv[2]) else 4)
