#!/bin/sh
# The macOS half of a release: Apple Silicon only (ruled — Intel Macs
# are not a target), built from a laptop rather than a runner. Builds
# the binary, the extension from the sibling checkout at the commit
# crates/duck/gloss.ref names, and the tarball — bin/, lib/ with the
# DuckDB library, share/glossql with the extension and the kits — opens
# the draft release on the pushed tag, uploads the tarball to it, and
# rewrites the tap formula with the artifact's checksum — publish the
# release, then copy that file to
# glossdb/homebrew-glossql/Formula/glossql.rb and push the tap.
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/^version = "\(.*\)"$/\1/p' Cargo.toml | head -1)
tag="v${version}"
name="glossql-${version}-aarch64-apple-darwin"
artifact="${name}.tar.gz"
gloss="${GLOSS_CHECKOUT:-../gloss}"
ref=$(cat crates/duck/gloss.ref)

if [ "$(git -C "$gloss" rev-parse HEAD)" != "$ref" ]; then
  echo "the extension checkout at $gloss is not at $ref (crates/duck/gloss.ref)" >&2
  exit 1
fi
(cd "$gloss" && GEN=ninja make release)

cargo build --locked --release -j8 -p glossql-serverd
stage="target/${name}"
rm -rf "$stage" && mkdir -p "$stage/bin" "$stage/lib" "$stage/share/glossql"
cp target/release/glossql "$stage/bin/"
cp target/release/build/libduckdb-sys-*/out/libduckdb.dylib "$stage/lib/"
cp "$gloss/build/release/repository/v2.0.0/osx_arm64/gloss.duckdb_extension" "$stage/share/glossql/"
cp -R "$gloss/kits" "$stage/share/glossql/kits"
tar -C target -czf "target/${artifact}" "$name"
sha=$(shasum -a 256 "target/${artifact}" | cut -d' ' -f1)

gh release view "$tag" >/dev/null 2>&1 \
  || gh release create "$tag" --draft --verify-tag --title "$tag" --notes ""
gh release upload "$tag" "target/${artifact}" --clobber

sed -e "s/{{version}}/${version}/g" -e "s/{{sha256}}/${sha}/g" \
  .github/homebrew/glossql.rb.tmpl > .github/homebrew/glossql.rb

echo "uploaded ${artifact} (sha256 ${sha})"
echo "formula at .github/homebrew/glossql.rb — publish the release, then copy to glossdb/homebrew-glossql/Formula/ and push"
