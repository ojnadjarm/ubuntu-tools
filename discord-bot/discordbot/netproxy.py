"""netproxy serve <sock> | relay <sock> <port> — the bot sandbox's only way out (adapted from code-review-netproxy).

serve (outside the sandbox): an HTTP CONNECT proxy on a unix socket that tunnels only to port 443 of Discord hosts.
relay (inside, where only loopback exists): 127.0.0.1:<port> → that unix socket.
"""
import asyncio
import os
import sys

ALLOW = ('discord.com', 'discord.gg', 'discordapp.com', 'discordapp.net')
def allowed(host, port):
    host = host.lower().rstrip('.')
    return port == 443 and any(host == d or host.endswith('.' + d) for d in ALLOW)


async def pipe(r, w):
    try:
        while data := await r.read(65536):
            w.write(data)
            await w.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        w.close()


async def handle_connect(r, w):
    try:
        head = await asyncio.wait_for(r.readuntil(b'\r\n\r\n'), 30)
        method, target, _ = head.split(b'\r\n', 1)[0].decode('latin-1').split(' ', 2)
        host, _, port = target.rpartition(':')
        if method != 'CONNECT' or not allowed(host, int(port or 0)):
            print(f'netproxy: refused {method} {target}', file=sys.stderr, flush=True)
            w.write(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n')
            await w.drain()
            w.close()
            return
        ur, uw = await asyncio.wait_for(asyncio.open_connection(host, int(port)), 30)
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, ValueError, OSError):
        w.close()
        return
    w.write(b'HTTP/1.1 200 Connection established\r\n\r\n')
    await w.drain()
    await asyncio.gather(pipe(r, uw), pipe(ur, w))


async def handle_relay(sock, r, w):
    try:
        ur, uw = await asyncio.open_unix_connection(sock)
    except OSError:
        w.close()
        return
    await asyncio.gather(pipe(r, uw), pipe(ur, w))


async def main(argv):
    if len(argv) == 2 and argv[0] == 'serve':
        if os.path.exists(argv[1]):
            os.unlink(argv[1])
        srv = await asyncio.start_unix_server(handle_connect, argv[1])
        os.chmod(argv[1], 0o600)
    elif len(argv) == 3 and argv[0] == 'relay':
        srv = await asyncio.start_server(lambda r, w: handle_relay(argv[1], r, w), '127.0.0.1', int(argv[2]))
    else:
        sys.exit(__doc__.splitlines()[0])
    async with srv:
        await srv.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main(sys.argv[1:]))
    except KeyboardInterrupt:
        pass
