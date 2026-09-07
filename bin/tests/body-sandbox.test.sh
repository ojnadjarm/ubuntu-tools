#!/usr/bin/env bash
# The sandbox's own test lives with the body it isolates; run.sh picks it up here.
exec bash "$HOME/the-dark-eye/body/test/body-sandbox.test.sh"
