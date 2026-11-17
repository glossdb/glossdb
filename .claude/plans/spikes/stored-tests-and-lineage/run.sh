#!/bin/sh
# Reruns the spike: about 30 seconds. Outputs cases.out, bench.out, parts.out.
set -e
cd "$(dirname "$0")"
[ -x .venv/bin/python ] || { uv venv -q .venv && uv pip install -q --python .venv/bin/python duckdb==2.0.0; }
mkdir -p run
.venv/bin/python cases.py > cases.out
.venv/bin/python bench.py > bench.out
.venv/bin/python parts.py > parts.out
.venv/bin/python walk.py > walk.out
