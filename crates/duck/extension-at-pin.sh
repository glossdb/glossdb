#!/bin/sh
# The glossql extension at a commit, into a directory: the kits and the
# language's two documents from the pinned tree; the loadable from the
# artifact the extension's own pipeline uploads for this platform on
# every run, looked up by the commit (the listing is open, the download
# needs a GitHub token in GH_TOKEN, any account's); else built from the
# tree, as the pipeline builds it. Run by CI and by the Dockerfile's
# extension stage.
#   extension-at-pin.sh <commit> <out-dir>
# GLOSSQL_ARCH names the platform in place of this machine's.
set -eu
ref="$1"
out="$2"
arch="${GLOSSQL_ARCH:-$(case "$(uname -m)" in x86_64) echo linux_amd64 ;; aarch64) echo linux_arm64 ;; *) echo unknown ;; esac)}"
work="$(mktemp -d)"
src="$work/glossql"
git clone --quiet --filter=blob:none https://github.com/glossdb/glossql "$src"
git -C "$src" checkout --quiet "$ref"
# the runs listing filters on the whole commit hash, never a prefix
sha="$(git -C "$src" rev-parse HEAD)"
mkdir -p "$out"
cp -r "$src/kits" "$out/kits"
cp "$src/SPEC.md" "$src/grammar.ebnf" "$out/"
fetched=
if [ -n "${GH_TOKEN:-}" ]; then
  api=https://api.github.com/repos/glossdb/glossql/actions
  # the extension's pipeline may still be building this commit: its build
  # takes about six minutes, a build here fifteen, so wait for it
  waited=0
  while [ "$waited" -lt 600 ] && curl -fsSL "$api/runs?head_sha=$sha&per_page=20" \
      | python3 -c 'import json, sys; sys.exit(0 if any(r["name"] == "Main Extension Distribution Pipeline" and r["status"] != "completed" for r in json.load(sys.stdin)["workflow_runs"]) else 1)'; do
    sleep 20
    waited=$((waited + 20))
  done
  for run in $(curl -fsSL "$api/runs?head_sha=$sha&per_page=20" \
               | python3 -c 'import json, sys; print(" ".join(str(r["id"]) for r in json.load(sys.stdin)["workflow_runs"] if r["name"] == "Main Extension Distribution Pipeline"))'); do
    url=$(curl -fsSL "$api/runs/$run/artifacts" \
          | python3 -c 'import json, sys; print(next((a["archive_download_url"] for a in json.load(sys.stdin)["artifacts"] if a["name"].endswith("-extension-" + sys.argv[1])), ""))' "$arch")
    [ -n "$url" ] || continue
    if curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -o "$work/extension.zip" "$url"; then
      python3 -m zipfile -e "$work/extension.zip" "$work/artifact"
      cp "$work/artifact/glossql.duckdb_extension" "$out/"
      echo "the extension at $ref: the $arch artifact of run $run"
      fetched=1
      break
    fi
  done
fi
if [ -z "$fetched" ]; then
  echo "the extension at $ref: built, no $arch artifact reached"
  if ! command -v ninja >/dev/null 2>&1; then
    if [ "$(id -u)" = 0 ]; then
      apt-get update && apt-get install -y --no-install-recommends cmake ninja-build
    else
      sudo apt-get update && sudo apt-get install -y --no-install-recommends cmake ninja-build
    fi
  fi
  (cd "$src" && git submodule update --quiet --init --depth 1 duckdb extension-ci-tools && GEN=ninja EXT_FLAGS=-DGLOSSQL_LAKE=OFF make release)
  cp "$src"/build/release/repository/v2.0.0/*/glossql.duckdb_extension "$out/"
fi
rm -rf "$work"
