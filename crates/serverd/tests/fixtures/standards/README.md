# The standards' schemas at the pin

The JSON schemas the two standard exports are validated against, verbatim.
`semantic_model()` is checked against the Apache Ossie schema and
`lineage_events()` against the OpenLineage schemas, by
`crates/serverd/tests/suite/standards.rs`.

| File | Source | Commit |
|---|---|---|
| `ossie-schema.json` | https://github.com/apache/ossie/blob/main/core-spec/ossie-schema.json (version 0.3.0.dev0, a draft) | `74a26befc83dd5f01f6177b4288efc8e0848a8f3` |
| `OpenLineage.json` | https://openlineage.io/spec/2-0-2/OpenLineage.json | OpenLineage/OpenLineage `a81dabd91ef52d08803394842f56bf9985094e32` |
| `ColumnLineageDatasetFacet.json` | https://openlineage.io/spec/facets/1-2-0/ColumnLineageDatasetFacet.json | OpenLineage/OpenLineage `d3e42a1883838735759ebdcc54fb5f4387474101` |

All three are under the Apache License 2.0, kept as `LICENSE`. Apache
Ossie (incubating), copyright 2026 The Apache Software Foundation.

Ossie's schema is a draft and still changes. To move the pin, fetch the
file at a new commit, replace it here, update the commit above, and run
the suite.
