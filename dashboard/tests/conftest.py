"""Puts the dashboard package on the import path before any test imports server; no test reads the real owner-todo ledger."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
os.environ["OWNER_TODO_LEDGER"] = os.path.join(HERE, "fixtures", "no-owner-todo.jsonl")
