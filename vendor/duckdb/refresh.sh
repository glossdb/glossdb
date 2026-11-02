#!/bin/sh
# Refresh the vendored DuckDB SQL guide — the pages the door serves as
# `doc://vendor/duckdb/sql/…` — from duckdb-web's tree for the DuckDB
# release the lock resolves, at one commit of that repository. Run at
# every DuckDB pin move; the serverd suite refuses a VERSION that is
# not the lock's.
#
#   vendor/duckdb/refresh.sh 2.0 <duckdb-web commit>
#
# The query syntax, the expressions, the functions and the data types
# are fetched; the statements are not, since the door serves reads and
# closes the rest, except the SELECT statement's own page. A page's
# front matter becomes its title line; the rest is the page as written.
set -eu
release="${1:?usage: refresh.sh <docs version, e.g. 2.0> <duckdb-web commit>}"
commit="${2:?usage: refresh.sh <docs version, e.g. 2.0> <duckdb-web commit>}"
here="$(cd "$(dirname "$0")" && pwd)"
upstream="docs/${release}/sql"
fetch() {
  gh api "repos/duckdb/duckdb-web/contents/$upstream/$1.md?ref=$commit" --jq '.content' | base64 -d
}
page() {
  dir="$here/sql/$(dirname "$1")"
  mkdir -p "$dir"
  fetch "$1" | awk '
    NR == 1 && $0 == "---" { front = 1; next }
    front && $0 == "---" { front = 0; printf "# %s\n", title; next }
    front { if ($0 ~ /^title: /) { title = substr($0, 8); gsub(/^"|"$/, "", title) }; next }
    { print }
  ' > "$here/sql/$1.md"
}
rm -rf "$here/sql"
for p in select from where groupby grouping_sets having orderby limit with window qualify filter unnest setops values sample; do
  page "query_syntax/$p"
done
for p in overview case cast comparison_operators in logical_operators star subqueries try; do
  page "expressions/$p"
done
for p in overview aggregates window_functions date datepart dateformat timestamp timestamptz time interval text pattern_matching regular_expressions numeric list array struct map nested lambda utility union enum blob bitstring variant; do
  page "functions/$p"
done
for p in overview numeric text boolean date time timestamp timezones interval list array struct map union enum nulls typecasting literal_types blob bitstring variant; do
  page "data_types/$p"
done
page "statements/select"
gh api "repos/duckdb/duckdb-web/contents/LICENSE?ref=$commit" --jq '.content' | base64 -d > "$here/LICENSE"
printf '%s\n%s\n' "$release" "$commit" > "$here/VERSION"
