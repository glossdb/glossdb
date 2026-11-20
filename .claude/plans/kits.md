# Kits plan

The target agreed with the project lead, and the steps towards it.
Nothing is started before the smoke test and the merge of
`snapshot-version`. It is prepared in place, in the two repositories as
they are, and moved last.

## The cut

The question for each piece: would someone who only wants to gloss a
lake need it?

| Part | What it is | Depends on |
|---|---|---|
| glossql | Glossing a lake: the language, the catalog, annotations by an agent or a person, properties with a schema, relationships, views (named SQL on the dataset), functions and tests with stored results, what is out of date, column lineage, one statement that brings results current, and `next` over those states. It names no vocabulary and no kind of view. It offers kits a numbered contract | DuckLake |
| The vocabulary kit | The business glossary's properties (`meaning`, `role`, `entity`, `unit`, `additivity`, `dimension`, `time_grains` and the others) and the few reads that say what the vocabulary states about an asset. Declarations and SQL only. The first kit to be declared stable | the contract |
| The data intelligence kit | Single values and metrics as kinds of view, a metric's series, profiles and the numeric evidence, the tests glossdb ships, the standard exports. SQL and its own native code | the contract, the vocabulary |
| Add-on kits | `harmonise`, spatial, `plan`, `outlook` | the contract, the vocabulary, the data intelligence kit where they read it |
| The server | MCP, the query endpoint, the console and data apps, sign-in, review by a person | all of the above |

- **A view is a table view by default.** A single value and a metric
  state their kind, and the kind is the data intelligence kit's.
- **A kit is a DuckDB extension** in the repository `glosskits`: a
  folder per kit with its manifest (name, version, stable or preview,
  what it requires), its SQL, its native code where it has any, and
  its suite. It is installed from a signed extension repository. Its
  code lives in the extension. A lake holds the kit's declarations as
  catalog rows and the kit's version; the version is the input by
  which an upgrade makes the kit's results due.
- **A kit adds rows to `next` in two ways:** a test brings its finding
  and fix for a judgement on one subject; a read of the kit, named by
  convention as the asset kinds are, brings what is not a judgement
  (a first step, a person's decision to carry, a load that does not
  fit its source).
- **A read belongs to the contract** when several kits need it or it is
  generic in kind (`dataset_cells`, `subject_column`,
  `glossql_relationship_checks`, the kind seam). A read one kit uses is
  that kit's code (`series_aggregate`, `glossql_additivity_cells`). A
  read that says what the vocabulary states is the vocabulary kit's.
- **Other vocabularies are not read.** The kits read this one by name.

## Steps, in place first

| # | Element | Risk | What it touches | Issue |
|---|---|---|---|---|
| 1 | Retire what has no caller: `glossql_service` (168 lines, no kit calls it), `json_schema_check`, the load fingerprint if `load_modes()` can do without it, and the lineage kit's macros nothing reads (`views_joins` and others; 20 of its 35 have no caller outside the kit, to be checked for use inside it) | Low | the extension | |
| 2 | (Now in `views.md`, with the kind in the definition's body.) The plain view is the default kind; a metric states its kind. Every skill, doc, fixture and golden that defines a metric follows | Medium: every metric an agent writes changes | the store, the lineage kit's places, the views kit, `SPEC.md`, the skills | |
| 3 | The kit contract, numbered: a kit's read states what it reads (the read tracker names four functions today); who owns a property's name (a user's own `unit` stops the vocabulary kit today) | High | the extension's runner and store, `SPEC.md` §5 and §6 | |
| 4 | glossql names no vocabulary: `role`, `entity` and `period` leave the runner with the additivity cells, which become the data intelligence kit's code | Medium | the extension | |
| 5 | glossql alone brings results current in one statement and has `next`: the generic rows (annotation states, tests, results out of date) and the read each kit adds | Medium | `results_due()` and `next` from the server's `goals` kit, the server's loop after a write | |
| 6 | The kit files regrouped into the target units, each with a manifest and a version recorded in the lake in place of the hash, still loaded as today | Medium | `kits/` in both repositories | #248 |
| 7 | Spike: glossql registers the macros of a kit on the stable C API, so a kit of SQL alone is small and survives DuckDB releases | Medium | the extension, a shim | |
| 8 | The move: the kits as extensions in `glosskits`, the vocabulary first; the repository published to a static prefix, its key compiled into the server, the image carrying the kits | High | both repositories, `glosskits`, CI | |
| 9 | `plan` and `outlook` back from the tag `before-cut`, on stored results and the kind seam | Medium | `glosskits` | #246, #174 |

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
  (73), the load fingerprint (14).
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

## Next issue

Not drafted until the merge. The project lead picks the first step.
