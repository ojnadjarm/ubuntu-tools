#!/usr/bin/env python3
"""pc_top.py — one-process /proc snapshot: CPU%, wakeups/s, RSS/PSS, IO bytes/s, unit per pid.

Two-sample window over raw /proc reads (no per-pid forks, no psutil — the fixture format
below needs exact control over which sample a read lands on). Field choices reused from
body/scripts/sample.sh and sentinel-runaway; see PLAN-PCTOOLS.md PT02.

Fixture testing: set PC_PROC=<dir> to redirect all reads under <dir> instead of /proc. Each
pid directory may carry "<name>.0" / "<name>.1" beside (or instead of) the plain "<name>" —
tick 0 is read before the window, tick 1 after; when a fixture has no plain file the current
tick's suffixed one is used. Live runs (no PC_FIXTURE) only ever read the plain files, twice,
with a real time.sleep(seconds) between the two reads.
"""
import argparse
import json
import os
import sys
import time

CLK_TCK = os.sysconf("SC_CLK_TCK")


def proc_root():
    return os.environ.get("PC_PROC", "/proc")


def sys_root():
    return os.environ.get("PC_SYS", "/sys")


def pfile(proc, pid, name, tick):
    """Path to <pid>/<name> for this tick, preferring the tick-suffixed fixture file."""
    suffixed = f"{proc}/{pid}/{name}.{tick}"
    if os.path.exists(suffixed):
        return suffixed
    return f"{proc}/{pid}/{name}"


def read_file(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def list_pids(proc):
    pids = []
    try:
        for name in os.listdir(proc):
            if name.isdigit():
                pids.append(int(name))
    except OSError:
        pass
    return sorted(pids)


def read_cmdline_basename(proc, pid):
    data = read_file(f"{proc}/{pid}/cmdline")
    if not data:
        return None
    argv0 = data.split("\0", 1)[0]
    return os.path.basename(argv0) if argv0 else None


def read_comm(proc, pid):
    data = read_file(f"{proc}/{pid}/comm")
    return data.strip() if data else "?"


def read_unit(proc, pid):
    """Last path element of /proc/<pid>/cgroup when it is a *.service or *.scope (quirks)."""
    data = read_file(f"{proc}/{pid}/cgroup")
    if not data:
        return "-"
    line = data.strip().splitlines()[-1] if data.strip() else ""
    path = line.split(":", 2)[-1] if line else ""
    last = path.rstrip("/").rsplit("/", 1)[-1]
    if last.endswith(".service") or last.endswith(".scope"):
        return last
    return "-"


def read_stat(proc, pid, tick):
    """cpu ticks (utime+stime) from /proc/<pid>/stat, field 14+15."""
    data = read_file(pfile(proc, pid, "stat", tick))
    if not data:
        return None
    # comm may contain spaces/parens; fields are counted from the closing paren.
    rparen = data.rfind(")")
    if rparen == -1:
        return None
    fields = data[rparen + 2:].split()
    try:
        utime, stime = int(fields[11]), int(fields[12])
    except (IndexError, ValueError):
        return None
    return utime + stime


def read_ctxt(proc, pid, tick):
    """voluntary + nonvoluntary ctxt switches from /proc/<pid>/status."""
    data = read_file(pfile(proc, pid, "status", tick))
    if not data:
        return 0
    vol = invol = 0
    for line in data.splitlines():
        if line.startswith("voluntary_ctxt_switches:"):
            vol = int(line.split(":", 1)[1].strip())
        elif line.startswith("nonvoluntary_ctxt_switches:"):
            invol = int(line.split(":", 1)[1].strip())
    return vol + invol


def read_io(proc, pid, tick):
    """(read_bytes, write_bytes) from /proc/<pid>/io — root-only for other users' pids."""
    data = read_file(pfile(proc, pid, "io", tick))
    if not data:
        return (0, 0)
    rd = wr = 0
    for line in data.splitlines():
        if line.startswith("read_bytes:"):
            rd = int(line.split(":", 1)[1].strip())
        elif line.startswith("write_bytes:"):
            wr = int(line.split(":", 1)[1].strip())
    return (rd, wr)


def read_rss_kb(proc, pid, tick):
    """VmRSS in kB from /proc/<pid>/status — cheap, used to rank before the smaps_rollup read."""
    data = read_file(pfile(proc, pid, "status", tick))
    if not data:
        return 0
    for line in data.splitlines():
        if line.startswith("VmRSS:"):
            try:
                return int(line.split()[1])
            except (IndexError, ValueError):
                return 0
    return 0


def read_rss_pss_kb(proc, pid, tick):
    """(rss_kb, pss_kb) from /proc/<pid>/smaps_rollup — the expensive read, top-N only."""
    data = read_file(pfile(proc, pid, "smaps_rollup", tick))
    if not data:
        return (None, None)
    rss = pss = None
    for line in data.splitlines():
        if line.startswith("Rss:"):
            rss = int(line.split()[1])
        elif line.startswith("Pss:"):
            pss = int(line.split()[1])
    return (rss, pss)


def read_rapl_uj(sysroot, tick):
    # pfile() is pid-shaped; RAPL has no pid, so read directly with the same tick convention.
    suffixed = f"{sysroot}/class/powercap/intel-rapl:0/energy_uj.{tick}"
    path = suffixed if os.path.exists(suffixed) else f"{sysroot}/class/powercap/intel-rapl:0/energy_uj"
    data = read_file(path)
    if not data:
        return None
    try:
        return int(data.strip())
    except ValueError:
        return None


def snapshot(pids, proc, tick):
    rows = {}
    for pid in pids:
        cpu = read_stat(proc, pid, tick)
        if cpu is None:
            continue
        ctxt = read_ctxt(proc, pid, tick)
        rd, wr = read_io(proc, pid, tick)
        rows[pid] = {"cpu": cpu, "ctxt": ctxt, "rd": rd, "wr": wr}
    return rows


def collect(seconds, proc):
    pids = list_pids(proc)
    fixture = bool(os.environ.get("PC_FIXTURE"))
    os.environ["PC_FIXTURE_TICK"] = "0"
    s0 = snapshot(pids, proc, 0)
    e0 = read_rapl_uj(sys_root(), 0)
    if fixture:
        pass  # deterministic fixture ticks: no wall-clock sleep needed
    else:
        time.sleep(seconds)
    os.environ["PC_FIXTURE_TICK"] = "1"
    s1 = snapshot([p for p in pids if p in s0], proc, 1)
    e1 = read_rapl_uj(sys_root(), 1)

    rapl_w = None
    if e0 is not None and e1 is not None and seconds > 0:
        rapl_w = max(0, e1 - e0) / 1e6 / seconds

    rows = []
    for pid, a in s0.items():
        b = s1.get(pid)
        if b is None:
            continue
        cpu_pct = max(0.0, (b["cpu"] - a["cpu"]) / CLK_TCK / seconds * 100) if seconds > 0 else 0.0
        wake = max(0.0, (b["ctxt"] - a["ctxt"]) / seconds) if seconds > 0 else 0.0
        io_r = max(0, b["rd"] - a["rd"]) / seconds if seconds > 0 else 0.0
        io_w = max(0, b["wr"] - a["wr"]) / seconds if seconds > 0 else 0.0
        comm = read_cmdline_basename(proc, pid) or read_comm(proc, pid)
        unit = read_unit(proc, pid)
        rss_kb = read_rss_kb(proc, pid, 1)
        rows.append({
            "pid": pid, "comm": comm, "cpu": round(cpu_pct, 2), "wake": round(wake, 1),
            "rss": rss_kb, "io_r": round(io_r, 1), "io_w": round(io_w, 1), "unit": unit,
        })
    return rows, rapl_w


def machine_footer():
    cores = os.cpu_count() or 0
    load = "n/a"
    la = read_file(f"{proc_root()}/loadavg")
    if la:
        load = " ".join(la.split()[:3])
    return cores, load


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--seconds", type=float, default=0.3)
    ap.add_argument("--sort", choices=["cpu", "wake", "io", "rss"], default="cpu")
    ap.add_argument("-n", "--limit", type=int, default=15)
    ap.add_argument("--unit", default=None)
    ap.add_argument("--all-users", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    proc = proc_root()
    rows, rapl_w = collect(args.seconds, proc)

    if args.unit:
        rows = [r for r in rows if args.unit in r["unit"]]

    key = {"cpu": "cpu", "wake": "wake", "rss": "rss", "io": None}[args.sort]
    if args.sort == "io":
        rows.sort(key=lambda r: r["io_r"] + r["io_w"], reverse=True)
    else:
        rows.sort(key=lambda r: r[key], reverse=True)
    rows = rows[: args.limit]

    # PSS is the expensive read: only for the rows that survived ranking.
    for r in rows:
        rss_kb, pss_kb = read_rss_pss_kb(proc, r["pid"], 1)
        r["rss"] = rss_kb if rss_kb is not None else r["rss"]
        r["pss"] = pss_kb if pss_kb is not None else 0

    if args.json:
        print(json.dumps(rows))
        return

    print(f"{'pid':>7} {'comm':<20} {'cpu%':>6} {'wake/s':>7} {'rss':>7} {'pss':>7} "
          f"{'io_r/s':>9} {'io_w/s':>9} {'unit':<24}")
    for r in rows:
        print(f"{r['pid']:>7} {r['comm']:<20.20} {r['cpu']:>6.1f} {r['wake']:>7.1f} "
              f"{r['rss'] // 1024:>6}M {r['pss'] // 1024:>6}M "
              f"{r['io_r'] / 1024:>8.1f}K {r['io_w'] / 1024:>8.1f}K {r['unit']:<24}")
    cores, load = machine_footer()
    footer = f"machine: {cores} cores, load {load}"
    if rapl_w is not None:
        footer += f", RAPL pkg {rapl_w:.1f} W"
    print(footer)


if __name__ == "__main__":
    main()
