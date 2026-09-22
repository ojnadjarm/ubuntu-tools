"""Machine constants shared by every module, and run() for the CLIs in ~/agents/bin."""
import os, socket, subprocess

HOME = os.path.expanduser("~")
BIN = os.path.join(HOME, "agents", "bin")
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOST = os.environ.get("HARNESS_HOST") or socket.gethostname()
BRAND = os.environ.get("HARNESS_BRAND", "")
PUBLIC_HOST = os.environ.get("HARNESS_TAILNET_FQDN") or HOST
PORT = 19998
BINDS = ["0.0.0.0", "::"]


def run(cmd, timeout=25):
    env = dict(os.environ, PATH=BIN + ":" + os.environ.get("PATH", "/usr/bin:/bin"))
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env).stdout
