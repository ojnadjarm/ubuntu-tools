"""Entry point: python -m discordbot bot|runner|gateway <netproxy socket>."""
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
elif cmd == 'gateway' and len(sys.argv) == 3:
    from urllib.parse import urlsplit

    from .gateway import run
    from .netproxy import relay

    async def gateway(cfg):
        """The system unit (T1634-V8): relay to the netproxy socket, then the bot, in one process."""
        async with await relay(sys.argv[2], urlsplit(cfg.proxy).port):
            await run(cfg)
    asyncio.run(gateway(Config.from_env()))
elif cmd == 'runner':
    from .runner import main
    asyncio.run(main())
else:
    sys.exit('usage: python -m discordbot bot|runner|gateway <netproxy socket>')
