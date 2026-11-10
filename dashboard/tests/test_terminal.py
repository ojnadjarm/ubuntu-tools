"""Dashboard terminal (T1548): unit shape and the owner-login gate on a fixture ttyd + caddy pair, never the real units."""
import base64, os, pathlib, shutil, socket, subprocess, tempfile, time, unittest, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
TERM = ROOT / "dashboard" / "terminal"
UNITS = ROOT / "units"
OWNER = "owner@example.test"
FRONT = "host.example.test:8476"


def unit(name):
    return (UNITS / name).read_text()


class TerminalUnits(unittest.TestCase):
    def test_terminal_shell_unit_binds_a_private_socket_only(self):
        u = unit("dash-terminal-tty.service")
        cmd = next(l for l in u.splitlines() if l.startswith("ExecStart="))
        self.assertIn("-i %t/dash-terminal/tty.sock", cmd)
        self.assertNotIn(" -p ", cmd)
        for flag in (" -W", " -O", " -m 3", " -b /tty"):
            self.assertIn(flag, cmd)
        self.assertIn("RuntimeDirectoryMode=0700", u)
        self.assertIn("Restart=on-failure", u)
        self.assertNotIn("User=", u)

    def test_terminal_front_unit_fails_closed_without_login(self):
        u = unit("dash-terminal.service")
        self.assertIn('[ -n "$TERMINAL_OWNER_LOGIN" ] || {', u)
        self.assertIn("RestartPreventExitStatus=78", u)
        self.assertIn("Restart=on-failure", u)
        self.assertNotIn("User=", u)

    def test_terminal_caddy_binds_loopback_only(self):
        c = (TERM / "Caddyfile").read_text()
        self.assertIn("http://:{$TERMINAL_PORT:8477} {", c)
        self.assertIn("\tbind 127.0.0.1\n", c)
        self.assertIn("admin off", c)
        self.assertNotIn("0.0.0.0", c)

    def test_terminal_no_login_in_tracked_files(self):
        login = os.environ.get("TERMINAL_OWNER_LOGIN") or os.environ.get("CHAT_OWNER_LOGIN")
        if not login:
            self.skipTest("no login in the environment")
        for p in [UNITS / "dash-terminal.service", UNITS / "dash-terminal-tty.service", TERM / "Caddyfile", *TERM.glob("web/*")]:
            self.assertNotIn(login, p.read_text(), p)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@unittest.skipUnless(shutil.which("ttyd") and shutil.which("caddy"), "ttyd and caddy needed")
class TerminalGate(unittest.TestCase):
    """A fixture pair in a temp runtime dir: ttyd runs `cat`, caddy uses the tracked Caddyfile on a free port."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="t1548-")
        run = pathlib.Path(cls.tmp, "dash-terminal")
        run.mkdir(mode=0o700)
        cls.port = free_port()
        cls.tty = subprocess.Popen(["ttyd", "-i", str(run / "tty.sock"), "-b", "/tty", "-W", "-O", "-m", "3", "cat"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        env = dict(os.environ, XDG_RUNTIME_DIR=cls.tmp, XDG_DATA_HOME=cls.tmp, XDG_CONFIG_HOME=cls.tmp, TERMINAL_OWNER_LOGIN=OWNER,
                   TERMINAL_PORT=str(cls.port), TERMINAL_WEB=str(TERM / "web"), HARNESS_TAILNET_FQDN="host.example.test")
        cls.caddy = subprocess.Popen(["caddy", "run", "--config", str(TERM / "Caddyfile"), "--adapter", "caddyfile"],
                                     env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            if (run / "tty.sock").exists():
                try:
                    socket.create_connection(("127.0.0.1", cls.port), 0.2).close()
                    break
                except OSError:
                    pass
            time.sleep(0.05)

    @classmethod
    def tearDownClass(cls):
        for p in (cls.caddy, cls.tty):
            p.terminate()
            p.wait(5)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def get(self, path, login=None):
        req = urllib.request.Request("http://127.0.0.1:%d%s" % (self.port, path), headers={"Host": FRONT})
        if login is not None:
            req.add_header("Tailscale-User-Login", login)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def ws(self, origin, login=OWNER):
        """Raw websocket handshake to /tty/ws; returns the status line."""
        key = base64.b64encode(os.urandom(16)).decode()
        host = FRONT
        head = ("GET /tty/ws HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
                "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: tty\r\nOrigin: %s\r\nTailscale-User-Login: %s\r\n\r\n") % (host, key, origin, login)
        with socket.create_connection(("127.0.0.1", self.port), 5) as s:
            s.sendall(head.encode())
            return s.recv(4096).split(b"\r\n", 1)[0].decode()

    def test_terminal_owner_gets_page_and_shell(self):
        st, body = self.get("/", OWNER)
        self.assertEqual(st, 200)
        self.assertIn(b'src="/tty/"', body)
        self.assertIn(b"xterm", self.get("/tty/", OWNER)[1][:200000])
        self.assertEqual(self.get("/tty/", OWNER)[0], 200)

    def test_terminal_missing_header_is_403(self):
        self.assertEqual(self.get("/")[0], 403)
        self.assertEqual(self.get("/tty/")[0], 403)
        self.assertEqual(self.get("/tty/token")[0], 403)

    def test_terminal_wrong_login_is_403(self):
        for bad in ("someone@example.test", OWNER.upper(), OWNER + "x", "*"):
            self.assertEqual(self.get("/tty/", bad)[0], 403, bad)

    def test_terminal_websocket_needs_same_origin(self):
        self.assertIn(" 101 ", self.ws("https://" + FRONT))
        self.assertNotIn(" 101 ", self.ws("https://evil.example.test"))
        self.assertIn(" 403 ", self.ws("https://" + FRONT, login="someone@example.test"))


if __name__ == "__main__":
    unittest.main()
