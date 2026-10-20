"""Load-aware wall budget, the Python twin of budget.sh (T491, T616): base × clamp(max(load/nproc × 4, 1 + psi/20), 1, 8)."""
import os


def budget(base):
    """Seconds allowed for a check whose quiet-machine limit is base; PC_LOADAVG, PC_PSI and PC_NPROC are fixtures."""
    load = float(open(os.environ.get('PC_LOADAVG', '/proc/loadavg')).read().split()[0])
    nproc = int(os.environ.get('PC_NPROC') or len(os.sched_getaffinity(0)))
    psi = 0.0
    try:
        for line in open(os.environ.get('PC_PSI', '/proc/pressure/cpu')):
            if line.startswith('some '):
                psi = float(line.split()[1].split('=')[1])
    except OSError:
        pass
    return round(base * min(8.0, max(1.0, load / nproc * 4, 1 + psi / 20)), 3)


if __name__ == '__main__':
    import sys
    print(f'{budget(float(sys.argv[1])):.3f}')
