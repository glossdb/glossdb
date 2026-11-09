---
name: glossql-release
description: How a glossql release is cut — the order of operations across both repos, the tag mechanics, and the sharp edges that have already cost a failed run. Use before tagging, changing the release workflow, or touching packaging.
---

# Releasing glossql

One release is one version everywhere: `version` in the workspace
`Cargo.toml` (`[workspace.package]`) is the single bump point, and
`glossdb --version` answers with it. The artifacts: a macOS arm64 tarball behind the brew tap — `bin/`
with the binary, DuckDB compiled in, `share/glossdb/`
with the glossql extension, its SPEC.md and `grammar.ebnf`, and the kits of both repositories — and the server image on GHCR
(`ghcr.io/glossdb/glossdb:<version>` and `:latest`, x86_64, built
from the `Dockerfile` at the tag, the extension at the commit
`crates/duck/glossql.ref` names from its pipeline's artifact). No model rides either: the
model service is glossthesi, released from its own repository on its
own cadence. **Never built**: macOS x86_64, ARM Linux, Jetson,
a cuda flavor, a Linux package (the image is the Linux artifact) —
ruled, don't propose them back.

The detail lives in the files themselves — `.github/workflows/
release.yml`, `.github/release-macos.sh`, the `Dockerfile`,
`docs/getting-started/installation.md`. What follows is the order, which is written
nowhere else.

## The order

1. If glossthesi's wire changed, glossthesi releases first — the
   server's suites against a running service are the check.
2. The extension's commit is pushed: `crates/duck/glossql.ref` names a
   commit on the extension's `main` whose push run of the distribution
   pipeline is green, or CI and the image build fail at the checkout.
   A pull request's run builds `linux_amd64` alone (the CI tools'
   reduced mode), so a branch commit leaves `linux_arm64` and
   `osx_arm64` with no artifact, and the image builds the extension
   from source without the lake beside it. Bump `version` in the workspace
   `Cargo.toml`, and the image tag in the `docker run` example of
   `docs/getting-started/installation.md`. Workspace `cargo test` green — a DuckDB
   pin move since the last release fails the vendored-guide test
   until `vendor/duckdb/refresh.sh <version> <commit>` has run.
3. Tag and push: `git tag v<version> && git push origin v<version>`,
   from a commit the `ci` workflow ran green on — the tag run builds,
   it does not test. The workflow builds the image and pushes it to
   GHCR — public the moment the push lands.
4. The laptop half: `.github/release-macos.sh` refuses unless the
   sibling checkout `../gloss` is at the pinned commit, builds the
   extension there and the binary here, stages the tarball, opens the
   draft release on the tag, uploads it, and renders
   `.github/homebrew/glossql.rb` with the real checksum.
5. Write the notes on the release: a very short overview and the
   fixes, one line each. Brief — the notes are not the docs, and
   never a commit list. When the image run is green and the tarball sits on
   the draft: `gh release edit v<version> --notes-file <notes>
   --draft=false`. Publish once, complete — that is the standing
   preference.
6. Copy the rendered file to
   `glossdb/homebrew-glossdb/Formula/glossdb.rb` and push the tap —
   after the publish, so the formula never points at a draft. Commit
   the rendered file here too.

## Sharp edges (each one has already fired)

- The image takes the extension from its pipeline's linux artifact
  at the pin when a GitHub token rides as the build argument
  `GH_TOKEN`, as the workflow passes its own (`crates/duck/
  extension-at-pin.sh`); without one, or for a platform the
  extension's matrix does not build, it compiles DuckDB to build the
  extension — an hour on a runner. The layer is cached by the pinned
  commit either way, so a tag without a pin move reuses it.
- A tag-push run uses the workflow file **at the tag's commit**. A
  workflow fix after tagging needs the tag re-pointed:
  `git tag -f v<version> && git push -f origin v<version>`.
  `workflow_dispatch` pushes the image as `:main` and `:sha-<commit>`
  — the road to an image between releases; `:latest` moves at a tag
  only.
- Draft assets are not served at the public download URL — brew
  fails against a draft with a bare "Download failed". Publishing is
  the fix, not the formula.
- Never put a formula in the tap before the tarball's sha256 exists;
  a placeholder breaks `brew install` publicly.
- A package's first push to GHCR lands **private** (packages do not
  inherit the repository's visibility); the package is made public
  once, in the org's package settings, and cannot be made private
  again. Until then `docker pull` answers "denied". `glossdb/glossdb`
  is public.
- The bump PR can fail `cargo deny check` on an advisory published
  since the last green run on `main`: the tree did not move, the
  advisory database did. The answer is a lock move to the fixed
  release, `cargo update -p <crate>@<version>`, in the bump PR —
  never a new entry in `deny.toml`'s ignore list for a fix that is a
  patch release away.
