"""Wake on the bot's nudge (T1421): ack each nudge at once, run one tick when the nudges have been quiet for a while."""
import asyncio
import os
import time


def mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return 0.0


async def debounce(path, quiet, on_nudge, on_quiet, clock=time.time, sleep=asyncio.sleep, step=2.0):
    """Call on_nudge for every new nudge, on_quiet once the nudge file is `quiet` s old; again if nudged during on_quiet."""
    mark = None
    while True:
        m = mtime(path)
        if m != mark:
            mark = m
            await on_nudge()
        left = m + quiet - clock()
        if left > 0:
            await sleep(min(step, left))
            continue
        await on_quiet()
        if mtime(path) == mark:
            return
