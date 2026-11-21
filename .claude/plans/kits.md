# Kits plan

The cut between glossql, the kits and the server, how a kit is
packaged, and the one list of steps towards it. It holds the clean-up
that followed the six-system test (143 tables, 15 planted faults,
`../glossval/evals/scenarios/retail-six-systems`).

## The cut

The question for each piece: would someone who only wants to gloss a
lake need it?

| Part | What it is | Depends on |
|---|---|---|
| glossql | Glossing a lake: the language, the catalog, annotations by an agent or a person, properties with a schema, relationships, views (named SQL on the dataset), functions and tests with stored results, what is out of date, column lineage from DuckDB's binder, one statement that brings results current, and `next` over those states. It names no vocabulary and no kind of view. It offers kits a numbered contract | DuckLake |
| The vocabulary kit | The business glossary's properties (`meaning`, `role`, `entity`, `unit` and the others) and the few reads that say what the vocabulary states about an asset. Declarations and SQL only. The first kit to be declared stable | the contract |
| The data intelligence kit | The profile of a column at each load, the comparison with the previous load, the tests glossdb ships; and, asked only where someone defines one, single values and metrics with their series, time grains and additivity; the standard exports | the contract, the vocabulary |
| Add-on kits | `harmonise`, spatial, `plan`, `outlook`, data apps | the contract, the vocabulary, the data intelligence kit where they read it |
| The server | MCP, the query endpoint, the console, sign-in, review by a person | all of the above |

- **A check compares what a load measured** with what an actor stated,
  with the previous load, or with its peers. It is red only against a
  statement or an acceptance. A fact the engine measures is shown as a
  fact.
- **Stating a property makes something answer at once.**
- **A kit adds rows to `next` in two ways:** a test brings its finding
  and fix; a read of the kit brings what is not a judgement.
- **A read belongs to the contract** when several kits need it or it is
  generic in kind. A read one kit uses is that kit's code.

## Packaging

The target is unchanged: **a kit is a DuckDB extension** in the
repository `glosskits` (`../glosskits`): a folder per kit with its
manifest (name, version, what it requires), its SQL, native code where
it has any, and its suite, installed from a signed extension
repository. A lake holds the kit's declarations as catalog rows and the
kit's version.

Measured on DuckDB 2.0.0: a shim that carries a kit's SQL and manifest
works, with a signed repository from a directory or a static HTTP
prefix, an upgrade, and loading from a process that links DuckDB
statically. The limits: no dependencies, no autoload and no update for
a custom repository; an extension cannot register a view; a C++ kit is
rebuilt for every DuckDB release; a kit on the stable C API cannot
register a macro outside the user's database; the repository syntax is
marked as still changing.

**Proposed adjustment, for the project lead to confirm:** two stages.
First a kit is its folder in `glosskits`, and the server loads the
folders named in its configuration at open, as it loads its own kit
files today. The same folder becomes an extension (step 12) when a kit
is handed to someone who does not run our server. The folder's layout
is the extension's from the start, so the second stage adds a shim and
a repository, not a rewrite.

## Steps

| # | Element | Risk | What it touches | When, issue |
|---|---|---|---|---|
| 1 | `core-layer` merged: the lean lineage, a result on a loaded table kept current, a rule that reads stored results retested, no expression text in the walker | | both repositories | The project lead |
| 2 | Harmonise as the first folder in `glosskits`, loaded by path. Stated: which columns of different systems are the same thing, with the factor to the common unit. Answers: the column against its peers, and against the previous load. A crosswalk is a declared relationship to its table; control totals are a rule view of two queries. It ships the column profile with magnitude and code set. The contract check and the source systems move with it | Medium | `glosskits`, the server's kit loading, `kits/harmonise` | Next |
| 3 | The contract gets what step 2 needs: a result as of the load before, a table as of the load before, and a profile stored at each load on a column that carries a statement | Medium | the extension, `SPEC.md` §6 | With 2 |
| 4 | A check is red only against a statement: the join, orphan and completeness tests show the measured fact and judge against a stated expectation | Medium | the views kit | After 2 |
| 5 | Retire what has no caller: `glossql_service`, `json_schema_check`, the load fingerprint if `load_modes()` can do without it, the lineage kit's macros nothing reads | Low | the extension | |
| 6 | glossql names no vocabulary: `role`, `entity` and `period` leave the runner with the additivity cells, which become the data intelligence kit's code | Medium | the extension | |
| 7 | glossql alone brings results current in one statement and has `next`: the generic rows (annotation states, tests, results out of date) and the read each kit adds. `results_due()` and `next` leave the server's `goals` kit | Medium | the extension, the server's loop after a write | |
| 8 | The kit contract, numbered: a kit's read states what it reads; who owns a property's name | High | the extension's runner and store, `SPEC.md` §5 and §6 | |
| 9 | The kit files regrouped into the target units, each with a manifest and a version recorded in the lake in place of the hash. Metrics, series, time grains and additivity are asked only in the data intelligence kit; data apps are an add-on | Medium | `kits/` in both repositories, the console | #248 |
| 10 | A source's notes become annotations in one statement, from a query. Measured: 5,620 single statements, 84 s at every size | Medium: a statement form | corpus, `SPEC.md`, the project lead | |
| 11 | Spike: glossql registers the macros of a kit on the stable C API, so a kit of SQL alone survives DuckDB releases | Medium | the extension, a shim | |
| 12 | The kits as extensions from a signed repository, the vocabulary first; its key compiled into the server, the image carrying the kits | High | both repositories, `glosskits`, CI | |
| 13 | `plan` and `outlook` back from the tag `before-cut`, on stored results | Medium | `glosskits` | #246, #174 |

Done before this list: the plain view as the default kind with the
kind in the definition's body (`views.md`); the mapping, the conditions
and the two checks that parsed a view's SQL are deleted.

After it, in `harness.md`: glossval tests of other shapes, governance,
a simulated collaboration, data intelligence apps.

## Measured

- glossql alone, with no server and no kit, on a new lake and on plain
  DuckLake tables it did not load: annotating, a property with a
  schema, a relationship, a function, a test, staleness after a plain
  `INSERT`, and a view's lineage all work. Missing alone: one statement
  that brings results current, and `next`.
- Of the extension's C++ about 1,250 lines served only the product
  before the clean-up: the additivity cells (577), `glossql_service`
  (168), `series_aggregate` (157), `dataset_cells` (156), the read
  tracker's branches for named functions (73), the load fingerprint
  (14). The lineage walker went from 1,576 to 1,162 lines.
- The six-system case at 0.05, 0.5 and 5 GB a load, on the lean
  lineage: all lineage together 0.97 MB (before: over 1.2 GB and a
  memory failure at 38 GiB); a reload with everything recomputed in
  103, 121 and 260 s; a plain read in 0.25 s.
- Across 72 evaluation runs the contract check led to a fix in 23. The
  checks that parsed a view's SQL named no column that was still wrong
  in 54 independent builds. On the six-system case stated units and
  reference names, one stored profile per column and rule views found
  14 of 15 faults.

## Next issue

Step 2, with step 3 as far as it needs it.
