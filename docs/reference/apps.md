# App authoring

A data app is a named set of parts: a manifest, pages, frames (SQL
queries) and chart specs. Authors write templates, SQL and specs,
never code. An app lives in the catalog or in the binary; nothing is
read from disk. How agents write apps over the metrics:
[data apps](../usage/data-apps.md).

## Where an app comes from

1. **Annotations.** Each part is its own annotation, written by an
   agent over MCP or by a person through any interface:
   - `app` on `<name>`: the manifest (`title`, optional `dataset`);
   - `app_page` on `<name>.<page>`: a page (`html`);
   - `app_frame` on `<name>.<frame>`: a query (`sql`);
   - `app_spec` on `<name>.<spec>`: a chart spec (`spec`).

   Each part has its own history; a person's part wins over an agent's.
   `app_parts` lists every part as a file (`index.html`,
   `frames/open.sql`, `specs/monthly.vl.json`). The server serves the
   parts as they were at the app's release, an `app_release`
   annotation on `<name>`, and the newest parts under `?draft`. An app
   with no release serves its draft; `app_releases` says what is
   released.
2. **The built-in.** The console ships in the binary and resolves the
   same way, after the catalog.

A part under the built-in's name is refused: it would replace the whole
app and the console's other pages would stop serving. Write an app
under its own name instead.

## The manifest

```glossql
GLOSS app ON console_mine AS $${"title": "My console"}$$;
```

- **No dataset.** The URL names it, `/<dataset>/app/<name>`, so one app
  serves every dataset and the bar's picker switches between them. A
  `dataset` key is accepted and ignored.
- **Names.** App, page, frame and spec names are single segments: ASCII
  letters and digits, `_`, `-`, `.`.
- **Pages.** `"pages": [{"name": "index", "title": "Overview"},
  {"name": "cash", "title": "Cash"}]` sets the order and the titles of
  the tabs; without it every page shows by its file name, `index`
  first. A page may carry a `"group"`: the bar draws a line where the
  group changes. A one-page app shows no tabs. Every page of an app
  from the catalog opens with the manifest's title; the console's
  pages are its tabs and print none.

## Frames

A frame is one SQL query served as Arrow IPC.

- **Parameters.** URL parameters bind as typed placeholders: `$from`
  in the SQL, `?from=…` on the URL. Values arrive as text; cast them in
  the SQL. A table function's argument binds the same way
  (`metric_series(grain := $grain)`). A placeholder nobody bound fails
  and names what the URL needs.
- **The dataset.** Not a parameter: the frame runs on the URL's
  dataset, and `current_dataset` names it in the SQL.
- **Read only.** Frames run as the person `app:<name>` and only read.
- **State is the URL.** The browser fetches each frame once per state
  and shares it across every tile bound to it. Drilling is navigation,
  and so is a viewer's window: `?grain=quarter&span=24` bind as
  `$grain` and `$span`. A frame reference's own parameters are the
  author's defaults (`frames/trend?grain=month&span=24`); the page URL
  overrides them, and only frames whose URL changed are fetched again.

Display logic (glyphs, classes, links) belongs in the frame's SQL, not
the template. The views and table functions (`open_questions`, `open_items`,
`metric_surfaces`, `metric_series()`, …) are the natural sources
([views and table functions](reads.md)); narrow a workspace-wide one
by joining `current_dataset`. `fmt_number(x)` and `fmt_change(p)`
print a number the console's way.

## Pages

Pages are Tera templates and may include each other. A page is markup.
Every page is served under a `Content-Security-Policy` that runs the
server's own assets and nothing the page carries: a `<script>`, an
`on…=` handler or a `javascript:` URL is not run, eval is not allowed,
and a Vega-Lite spec runs in Vega's interpreter. Inline style is
allowed. The server ships the only JavaScript, all vendored: htmx,
Vega-Lite (Vega, vega-embed, vega-interpreter), Arrow JS, and the
tiles below.

## Tiles

### gl-rows

```html
<gl-rows frame="frames/open" empty="no open questions">
  <template>…{subject} — {assumption}…</template>
</gl-rows>
```

Renders a frame through the author's `<template>`: every `{field}` in
text or attribute values takes the row's value, formatted like a table
cell. With `join="frames/y" on="key"`, the row of a second frame with
the same key merges into each row (its fields win): how a catalog
frame and a data frame meet in one list. Substitution is literal; a
frame that feeds an `href` returns a URL-ready value. A substituted
`href` or `src` with a script-capable scheme becomes `#`. An empty
frame shows its `empty` text; a capped one says so in its footer.

### gl-chart

`<gl-chart frame="frames/x" spec="specs/x.vl.json" empty="…">`

A Vega-Lite view over the frame. The spec binds the named data source
`frame`; the width defaults to the container. An empty frame shows the
`empty` text instead of a blank chart.

### gl-table

`<gl-table frame="frames/x" rows="50" empty="…">`

The frame as an HTML table, every column in the frame's order, the
first N rows (default 50), the total row count in the footer.

### gl-value

`<gl-value frame="frames/kpis" field="billings" delta-field="billings_delta" unit="days" format="compact" good="up">`

One number from the frame's first row, with an optional change beside
it. `format` is `compact | days | raw | month | text` (`text` passes a
word such as a band through unformatted); `good` says which direction
reads as healthy. The SQL computes the change; the tile only shows it.

### gl-window

`<gl-window frame="frames/axes">`

The viewer's grain and span as links over the page URL (`grain`,
`span`). It reads the metric's finest grain from a `metric_axes()`
frame and offers the grains from there up.

### gl-query

`<gl-query dataset="<dataset>" rows="50">`

A query of the viewer's own: a text area, a run button, the rows as a
table, and the result to save as CSV or as the Arrow stream. It posts
to `/<dataset>/query` and runs reads only (SELECT, WITH, DESCRIBE,
SHOW, EXPLAIN), saying so for anything else; the server's refusal is
shown as its text. A page opened with `?sql=` runs that query on load,
so a query is a link; a `sql` attribute does the same for a page that
knows its query. A header click sorts the rows in the browser. Rows
page in steps of `rows`; the downloads keep the whole result.

### gl-graph

`<gl-graph nodes="frames/x" edges="frames/y" empty="…">`

Column lineage over two frames. Nodes are one row per column (`node`,
`kind` as `table` or `metric`, `col`, `ord`, `role`); edges one row per
edge (`src`, `dst` as column paths, `kind` as `m2o`, `o2o` or
`reads`). dagre lays the tables out along their keys, the metrics stack
on the right. Columns nothing touches fold under a count; hover
follows a column; a click puts it in the URL as `focus`.

## Writes and refresh

The console takes two writes, a review decision and a re-measure. The
server answers each with an event, never a navigation: a decision with
`HX-Trigger: glossql:written`, on which the browser drops its cached
catalog frames; a re-measure (every measurement stored before the last
change run again, and every one a metric or a test reads that was never
made, `open_items`' `never measured` rows) with `glossql:remeasured,
glossql:written`, on which the cached data frames drop too, since a
re-measure can change the numbers and a decision cannot. Every tile
fetches again in place.

## The console as an example

`crates/apps/builtin/console/` is the reference app and each dataset's
own page (`/<dataset>/app` opens it): pages `index.html` (the review
queue), `metrics.html`, `quality.html`, `glossary.html`,
`lineage.html`, `export.html` and `query.html`; frames over the views
and table functions, `metric_series()`, `metric_axes()`,
`forecast_points()`, `plan_points()`, `metric_sources()` and `imports`;
two specs. Every built-in frame runs under the test suite. What each
page shows: [the console](../usage/console.md).
