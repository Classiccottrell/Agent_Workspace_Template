#!/usr/bin/env bash
#
# deps.sh — CLI dependency versions the workspace template was last verified
# against. Sourced by bootstrap.sh --check to flag upstream version drift.
# This is informational only — it never blocks setup. Re-run the probes in
# bootstrap.sh's --check output and update the values below when re-verifying.
#
# Last verified: 2026-07-09

TESTED_CLAUDE="2.1.206 (Claude Code)"
TESTED_AGY="1.1.0"
TESTED_GEMINI="0.47.0"
TESTED_GH="gh version 2.96.0 (2026-07-02)"
TESTED_NODE="v24.1.0"
TESTED_NPX="11.6.3"
TESTED_PYTHON3="Python 3.9.6"
