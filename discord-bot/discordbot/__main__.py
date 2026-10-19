"""Entry point: python -m discordbot bot|runner."""
import asyncio
import logging
import sys

from .config import Config

logging.basicConfig(level=logging.INFO, format='%(name)s %(levelname)s %(message)s')
logging.getLogger('discord').setLevel(logging.WARNING)
logging.getLogger('discord.client').setLevel(logging.ERROR)
cmd = sys.argv[1] if len(sys.argv) > 1 else ''
if cmd == 'bot':
    from .gateway import run
    asyncio.run(run(Config.from_env()))
elif cmd == 'runner':
    from .runner import main
    asyncio.run(main())
else:
    sys.exit('usage: python -m discordbot bot|runner')
