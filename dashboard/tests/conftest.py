"""One fixture vault for the whole run, set before any test imports server."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["NOTES_VAULT_DIR"] = os.path.join(HERE, "fixtures", "vault")
sys.path.insert(0, os.path.dirname(HERE))
