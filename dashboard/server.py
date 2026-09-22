#!/usr/bin/env python3
"""Phone-first status page for this machine: the unit's entry point; the code lives in dash/."""
import sys, types
from dash import cache, env, http, routes
from dash.services import files, notes, search, sites, state, system, thumbs, voice

MODULES = (env, cache, routes, http, system, sites, files, thumbs, notes, search, voice, state)


class Facade(types.ModuleType):
    """`server.X` reads X from the dash module that defines it; `server.X = v` rebinds it in every module holding X."""

    def __getattr__(self, name):
        for m in MODULES:
            if name in vars(m):
                return vars(m)[name]
        raise AttributeError("module 'server' has no attribute %r" % name)

    def __setattr__(self, name, value):
        owners = [m for m in MODULES if name in vars(m)]
        for m in owners:
            setattr(m, name, value)
        if not owners:
            super().__setattr__(name, value)


sys.modules[__name__].__class__ = Facade

if __name__ == "__main__":
    http.main()
