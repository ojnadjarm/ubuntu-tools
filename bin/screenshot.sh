#!/bin/bash
# Deprecated wrapper: use `pc shot`.
exec "$(dirname "$(readlink -f "$0")")/pc" shot "$@"
