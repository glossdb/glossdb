# App authoring

A data app is a named set of parts: a manifest, pages, frames (SQL
reads) and chart specs. An author writes markup, SQL and specs, and no
script. An app is stored in the catalog as annotations and served at
`/<dataset>/app/<name>`. The console is an app of the same kind that
ships in the binary.

## The parts

Each part is one annotation, written by an agent or a person:

| Property | On | Body |
|---|---|---|
| `app` | `<name>` | the manifest: `title`, optional `pages` |
| `app_page` | `<name>.<page>` | `html` |
| `app_frame` | `<name>.<frame>` | `sql` |
| `app_spec` | `<name>.<spec>` | `spec`: a Vega-Lite spec as text |
| `app_release` | `<name>` | `note`; optional `at`, the time of an earlier release to return to |

```glossql
USE stays;
GLOSS app ON occupancy_board AS $${"title": "Occupancy"}$$;
GLOSS app_frame ON occupancy_board.trend AS $${
  "sql": "SELECT period, value FROM metric_series(view := 'occupancy', grain := $grain) WHERE dimension = '' ORDER BY period"
}$$;
GLOSS app_page ON occupancy_board.index AS $${
  "html": "<h1>Occupancy</h1><gl-table frame=\"frames/trend?grain=month\" rows=\"24\"></gl-table>"
}$$;
GLOSS app_release ON occupancy_board AS $${"note": "first version"}$$;
```

- Names are single segments: ASCII letters, digits, `_`, `-`, `.`.
- A person's part wins over an agent's. `app_parts` lists each part
  as a file (`index.html`, `frames/trend.sql`, `specs/trend.vl.json`).
- The server serves the parts as they were at the app's release, and
  the newest parts under `?draft`. An app without a release serves its
  draft. `app_releases` lists the releases.
- A part under the console's name is refused.
- The manifest's `pages` sets the tabs' order and titles:
  `[{"name": "index", "title": "Overview"}, {"name": "rooms", "title": "Rooms"}]`.
  The URL names the dataset, so one app serves each dataset.

## Frames

A frame is one SQL read, served as Arrow IPC.

- URL parameters bind as placeholders: `$grain` in the SQL,
  `?grain=month` on the URL. Values arrive as text. A placeholder
  nobody bound fails and names what the URL needs.
- A frame runs on the URL's dataset, read-only, as the actor
  `app:<name>`.
- A frame reference's own parameters are the author's defaults
  (`frames/trend?grain=month`); the page URL overrides them.
- Put display logic in the SQL. `fmt_number(x)` and `fmt_change(p)`
  print a number and a change as the console does.

## Pages

Pages are Tera templates. Each is served under a
`Content-Security-Policy` that runs the server's own scripts only: a
`<script>`, an `on…=` handler or a `javascript:` URL in a page does
not run. Inline style is allowed. The server ships htmx, Vega-Lite,
Arrow JS, dagre and the tiles below.

## Tiles

| Tile | Attributes | Shows |
|---|---|---|
| `gl-table` | `frame`, `rows` (default 50), `empty` | the frame as a table, with the row count |
| `gl-rows` | `frame`, `rows`, `empty`; `join`, `on` | each row through the author's `<template>`; `{field}` takes the row's value. `join` merges a second frame's row with the same `on` key |
| `gl-value` | `frame`, `field`, `format` (`compact` or `text`) | one value from the frame's first row |
| `gl-chart` | `frame`, `spec`, `empty` | a Vega-Lite chart; the spec binds the data source named `frame` |
| `gl-window` | `frame` | links that set `grain` and `span` on the page URL, from the metric's floor up; the frame reads `view_summary()` |
| `gl-query` | `dataset`, `rows`, `sql` | a query pane for reads, with CSV and Arrow download; `?sql=` on the page URL runs a read on load |
| `gl-graph` | `nodes`, `edges`, `empty` | column lineage. Nodes: `node`, `kind` (`table`, `view`), `col`, `ord`, `role`. Edges: `src`, `dst`, `kind` (`m2o`, `o2o`, `reads`) |

```html
<gl-rows frame="frames/open" empty="no open questions">
  <template><p>{subject}: {assumption}</p></template>
</gl-rows>
<gl-chart frame="frames/trend?grain=month" spec="specs/trend.vl.json"></gl-chart>
<gl-value frame="frames/latest" field="value"></gl-value>
```

A substituted `href` or `src` with a script-capable scheme becomes
`#`.

## Writes and refresh

An app's pages read. The console adds one write, a review decision,
answered with the event the tiles refetch on (`glossql:written`).

## The console as an example

`crates/apps/builtin/console/` is the reference app: the pages
`index`, `model`, `history`, `lineage`, `glossary`, `views`,
`quality`, `review`, `export` and `query`, their frames over the reads
in [reads](reads.md), and two chart specs.
