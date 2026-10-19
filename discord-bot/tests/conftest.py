"""pytest under the system python: put the bot's venv site-packages (aiohttp, discord.py) on the path."""
import glob
import os
import sys

sys.path[:0] = glob.glob(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                      '.venv/lib/python3*/site-packages'))
