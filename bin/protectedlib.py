"""Python client of the protected-projects matcher (bin/protected, T1513): EREs per project, fails closed."""
import os
import re
import subprocess


def eres(kind):
    """[(project, compiled ERE)] for a kind (repo path container unit text); text EREs match lowercased values."""
    exe = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'protected')
    out = subprocess.run([exe, 'eres', kind], capture_output=True, text=True, check=True, timeout=10).stdout
    return [(n, re.compile(e)) for n, e in (line.split('\t', 1) for line in out.splitlines())]


def project(pairs, value):
    """The first project of eres() pairs whose ERE matches value, else None."""
    return next((n for n, e in pairs if e.search(value)), None)


def lexical_paths():
    """Protected repo and path entries expanded lexically (never stat'ed); raises when the matcher fails."""
    exe = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'protected')
    out = [subprocess.run([exe, 'words', k], capture_output=True, text=True, check=True, timeout=10).stdout for k in ('repo', 'path')]
    return sorted({p for o in out for p in o.splitlines() if p})
