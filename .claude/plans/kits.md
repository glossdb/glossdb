# Kits plan

Draft of the target, for the project lead to correct. Nothing in it is
built, and nothing is started before the smoke test and the merge of
`snapshot-version`.

## The cut

The question for each piece: would someone who only wants to gloss a
lake need it?

| Part | What it is | Depends on |
|---|---|---|
| glossql | Glossing a lake: the language, the catalog, annotations by an agent or a person, properties with a schema, relationships, functions and tests with stored results, what is out of date, column lineage, and `next` over those generic states. It knows no vocabulary and no metric | DuckLake |
| The data intelligence kit | What glossdb adds: the business vocabulary, table views, single values and metrics with their series, profiles and the numeric evidence, the tests glossdb ships, the standard exports. SQL and its own native code. One unit, versioned together, because its pieces read each other | glossql's kit contract |
| Add-on kits | `harmonise`, spatial, `plan`, `outlook` | the contract; the data intelligence kit where they read it |
| The server | MCP, the query endpoint, the console and data apps, sign-in, review by a person | all of the above |

A kit is a DuckDB extension in the repository `glosskits`, a folder per
kit with its manifest (name, version, stable or preview, what it
requires), its SQL, its native code where it has any, and its suite.
It is installed from a signed extension repository. Its code lives in
the extension. A lake holds the kit's declarations as catalog rows and
the kit's version; the version is the input by which an upgrade makes
the kit's results due.

## Measured

- glossql alone, with no server and no kit, on a new lake and on a
  lake of plain DuckLake tables it did not load: annotating, a
  property of one's own with a schema, a relationship, a function, a
  test, staleness after a plain `INSERT`, and a view's column lineage
  all work. Missing alone: one statement that brings results current,
  and `next`.
- Of 9,285 lines of C++ in the extension about 1,250 serve only the
  product: the additivity cells (577), `glossql_service` (168),
  `series_aggregate` (157), `dataset_cells` (156), the lineage's shape
  code (about 90), the read tracker's branches for named functions
  (73), the load fingerprint (14). Of the extension's kit SQL the
  lineage kit is generic; the vocabulary, quality and spatial kits are
  product or add-on.
- A kit as an extension works on DuckDB 2.0.0: a shim that carries the
  kit's SQL and manifest, a signed repository from a directory and
  from a static HTTP prefix, an upgrade, loading from a process that
  links DuckDB statically, a dependency check in SQL at load. The
  harmonise kit split that way gives the same stored results.
- DuckDB offers no dependencies, no autoload and no update for a
  custom repository; an extension cannot register a view; a C++ kit is
  rebuilt for every DuckDB release, a kit on the stable C API is not
  but cannot register a macro outside the user's database. The
  repository syntax is marked as still changing.

## Open

| Element | Risk | What it touches | When |
|---|---|---|---|
| The line itself: which pieces are glossql and which the data intelligence kit; one kit or several; where `next` is | High: it decides every row below | this plan | First, with the project lead |
| The kit contract, numbered: how a kit's native read says what it reads (today the read tracker names `dataset_cells`, `series_aggregate`, `glossql_additivity_cells` and `glossql_relationship_checks`); how a kit names a place or an asset kind (the kind seam); who owns a property's name (a user's own `unit` stops the vocabulary kit today) | High | the extension's runner and store, `SPEC.md` §5 and §6 | After the line |
| glossql names no vocabulary and no metric: `role`, `entity` and `period` in the runner, the `metric` default and `x-kind` in the store and the lineage kit's places, `series_aggregate` and the metric places in `SPEC.md` §6 | Medium | the extension | With the contract |
| glossql alone brings results current in one statement, and has `next` over annotation states, tests and results that are out of date | Medium | `results_due()` and `next` from the server's `goals` kit, the server's loop after a write | With the contract |
| glossql registers the macros of a kit on the stable C API, so a kit of SQL alone is small and survives DuckDB releases. Spike first | Medium | the extension, the shim | After the contract |
| The data intelligence kit as the first extension: the vocabulary, `core`, `views` and quality kits with `series_aggregate`, `dataset_cells` and the additivity cells as its native code | High: most of today's kit SQL and 1,250 lines of C++ move | both repositories, `glosskits` | After the spike |
| An upgrade on a workspace that has values | Medium | the extension | With the first kit, #248 |
| `harmonise` and spatial as kits; `plan` and `outlook` back from the tag `before-cut`, on stored results and the kind seam | Medium | `glosskits` | After the first kit, #246, #174 |
| The repository: published from `glosskits` to a static prefix (GitHub Pages can serve the layout, release assets cannot), the key compiled into the server, the image carrying the kits | Low | CI, the server's open | With the first kit |

## Next issue

None drafted: the first row is a session with the project lead.
