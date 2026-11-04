#!/bin/sh
# The macOS half of a release: Apple Silicon only (ruled — Intel Macs
# are not a target), built from a laptop rather than a runner. Builds
# the binary, the extension from the sibling checkout at the commit
# crates/duck/glossql.ref names, and the tarball — bin/ with DuckDB
# compiled in, share/glossdb with the extension, its SPEC.md and
# grammar.ebnf, and the kits of both repositories — opens
# the draft release on the pushed tag, uploads the tarball to it, and
# rewrites the tap formula with the artifact's checksum — publish the
# release, then copy that file to
# glossdb/homebrew-glossdb/Formula/glossdb.rb and push the tap.
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/^version = "\(.*\)"$/\1/p' Cargo.toml | head -1)
tag="v${version}"
name="glossdb-${version}-aarch64-apple-darwin"
artifact="${name}.tar.gz"
gloss="${GLOSSQL_CHECKOUT:-../gloss}"
ref=$(cat crates/duck/glossql.ref)

if [ "$(git -C "$gloss" rev-parse HEAD)" != "$ref" ]; then
  echo "the extension checkout at $gloss is not at $ref (crates/duck/glossql.ref)" >&2
  exit 1
fi
(cd "$gloss" && GEN=ninja make release)

cargo build --locked --release -j8 -p glossdb-serverd
stage="target/${name}"
rm -rf "$stage" && mkdir -p "$stage/bin" "$stage/share/glossdb"
cp target/release/glossdb "$stage/bin/"
cp "$gloss/build/release/repository/v2.0.0/osx_arm64/glossql.duckdb_extension" "$stage/share/glossdb/"
cp "$gloss/SPEC.md" "$gloss/grammar.ebnf" "$stage/share/glossdb/"
cp -R "$gloss/kits" "$stage/share/glossdb/kits"
cp -R kits/. "$stage/share/glossdb/kits/"
tar -C target -czf "target/${artifact}" "$name"
sha=$(shasum -a 256 "target/${artifact}" | cut -d' ' -f1)

gh release view "$tag" >/dev/null 2>&1 \
  || gh release create "$tag" --draft --verify-tag --title "$tag" --notes ""
gh release upload "$tag" "target/${artifact}" --clobber

sed -e "s/{{version}}/${version}/g" -e "s/{{sha256}}/${sha}/g" \
  .github/homebrew/glossql.rb.tmpl > .github/homebrew/glossql.rb

echo "uploaded ${artifact} (sha256 ${sha})"
echo "formula at .github/homebrew/glossql.rb — publish the release, then copy to glossdb/homebrew-glossdb/Formula/ and push"
