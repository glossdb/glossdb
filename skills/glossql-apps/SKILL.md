---
name: glossql-apps
description: Write a data app on the glossdb web interface — a page at /<dataset>/app/<name>, written as annotations (app, app_page, app_frame, app_spec). Frames are SQL, tiles place what a frame computed, filters live in the URL. Use when someone needs to look at what a dataset serves, after the views exist.
---

# Data apps

A data app is a page at `/<dataset>/app/<name>`. Its URL is its whole
state: every filter a reader picks goes into the query string, so a
filtered page is a link they can send. Define the views first; an app
reads them. Agree in chat what the page is for and which tiles it
shows, write it, hand over the URL, and change it as the person
reacts.

The console (`/<dataset>/app/console`) is built in. Write your app
beside it under its own name; an annotation under the name `console`
is refused.

## An app is annotations

One annotation per part. Writing a part again replaces it. The
subject starts with the app's name, under the dataset of the call.

| Property | Subject | Is |
|---|---|---|
| `app` | `depots` | the manifest: `{"title": "…"}` |
| `app_page` | `depots.index` | a page: `{"html": "…"}` |
| `app_frame` | `depots.monthly` | a frame, `frames/monthly`: `{"sql": "…"}` |
| `app_spec` | `depots.trend` | a chart spec, `specs/trend.vl.json`: `{"spec": "…"}` |

```glossql
GLOSS app ON depots AS $${"title": "Depot review"}$$;
GLOSS app_frame ON depots.monthly AS $${"sql":
  "SELECT period, value FROM metric_series(grain := 'month') WHERE metric = 'parcels_delivered' AND dimension = '' ORDER BY period"}$$;
```

The manifest names no dataset: the URL does, so one app serves each
dataset of the workspace. `"pages": [{"name": "index", "title":
"Overview"}, …]` in the manifest sets the order and titles of the
tabs; without it each page shows by its name, `index` first. The
shell prints the manifest's title on every page.

```sql
SELECT app, path, actor_kind FROM app_parts ORDER BY app, path
```

What you write is the draft. Until the first release, readers see it
at the plain URL. A release is one annotation; from then on the plain
URL serves each part as it was at the release, and `?draft` shows
your later edits. To go back to an earlier release, give its time as
`app_releases` prints it: `{"at": "2026-09-23T09:00:00.000Z"}`.

```glossql
GLOSS app_release ON depots AS $${"note": "first version"}$$;
```

```sql
SELECT app, "at", note, released_at FROM app_releases
```

## Frames are SQL

A frame is one SELECT. The browser fetches each frame once per state,
and every tile bound to it shares the result. A frame can read
whatever a call can: a view by its name, `metric_series()`,
`view_summary()`, `view_tests()`, the catalog tables.

- **URL parameters bind as placeholders**: `$depot` in the SQL,
  `?depot=007` in the URL. Each arrives as text: cast it
  (`CAST($from AS DATE)`). A placeholder without a value fails the
  request and names it; extra parameters are ignored. A placeholder
  binds a value, not a table or view name. A tile's frame reference
  can carry defaults (`frames/trend?grain=month`); the page URL
  overrides them.
- **The dataset is not a parameter.** The frame runs on the dataset
  of the URL.
- **Compute display logic in the frame.** A label, a percentage, a
  CSS class chosen by a result is a column. A page places values.
- **Cast text built by functions**: a column built with `concat_ws`,
  `coalesce` or a JSON function needs `arrow_cast(x, 'Utf8')`, or the
  browser shows `Unrecognized type`.
- **Say when a list is cut**: a top N says so in the tile's chip or
  note.

```sql
SELECT period, value FROM metric_series(grain := CAST($grain AS VARCHAR))
WHERE metric = CAST($metric AS VARCHAR) AND dimension = '' ORDER BY period
```

## Pages place what frames computed

A page is a tera template that extends `shell.html`. It carries no
script: a `<script>`, an `on…=` handler or a `javascript:` URL is
served as text and does not run.

```html
{% extends "shell.html" %}
{% import "modules/tiles.html" as tiles %}
{% block main %}
<div class="tiles">
  {{ tiles::value(frame="frames/totals", field="parcels", label="Parcels this month",
       chip="parcels_delivered", note="completed deliveries only") }}
  {{ tiles::chart(frame="frames/monthly", spec="specs/trend.vl.json",
       title="Parcels by month", chip="parcels_delivered") }}
</div>
{% endblock %}
```

- `tiles::value(frame, field, label, …)`: one number; `format` is
  `compact` or `text` (for a word).
- `tiles::chart(frame, spec, …)`: a vega-lite spec over the frame.
- `<gl-table frame="frames/<name>" rows="50">`: the frame as a table.
- `<gl-rows>` with a `<template>`: a list where you place each field
  by name (`{depot}`); `join="frames/<name>" on="<key>"` merges a
  second frame's row into each row by key.
- `<gl-window frame="frames/<name>">`: links for the reader's grain
  and span, from a frame over `view_summary()`.
- `<gl-graph nodes="frames/<nodes>" edges="frames/<edges>">`: column
  lineage, from frames over `relationships` and `column_mapping()`.
- **The chip** names where a tile's number comes from, the view or
  the read; `note` is its hover text.

An `app_spec` is vega-lite JSON over the frame's columns. Keep it to
marks and encodings; filter and aggregate in the frame. Set `$schema`
to the major the server serves,
`https://vega.github.io/schema/vega-lite/v6.json`. The spec names the
tile's frame as `{"data": {"name": "frame"}}`.

A page reads and does not write. The web interface takes one write:
the console's review form. What an app should change, change with a
statement.
