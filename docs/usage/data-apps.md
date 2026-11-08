# Data apps

A data app is a page over the metrics, written by an agent and stored
in the catalog. It is served at `/<dataset>/app/<name>`, and its URL is
its whole state: the dataset is the first path segment and every filter
is in the query string, so any view is a link you can send. An app names
no dataset of its own, so one app serves every dataset in the
workspace. The full authoring reference is
[app authoring](../reference/apps.md).

## An app is annotations

Each part of an app is one annotation, so you can change a frame
without rewriting the app, and each part keeps its own history. The
property says what kind of file the part is: `app` (the manifest),
`app_page` (a page template), `app_frame` (a SQL frame), `app_spec` (a
Vega-Lite spec). The asset says where it goes.

```glossql
GLOSS app ON delivery AS $${"title": "Monday operations"}$$;
GLOSS app_frame ON delivery.monthly AS $${"sql":
  "SELECT date_trunc('month', date) AS period, sum(value) AS value FROM throughput GROUP BY 1 ORDER BY 1"}$$;
```

`app_parts` lists an app's parts, one row per file.

## Draft and release

Every part you write is the draft. A release is one annotation:

```glossql
GLOSS app_release ON delivery AS $${"note": "Monday operations, first cut"}$$;
```

- Readers see, for each part, the newest version written at or before
  the release. The draft stays at `?draft` on the same URLs, and the
  bar says which one is shown.
- An app nobody released serves its draft.
- To go back to an earlier release, release with its time:
  `{"at": "<released_at>"}`, as `app_releases` lists it.
- A person's release outranks an agent's.

Data and metadata reach every reader as soon as they are written; only
the app's own parts wait for a release.

## Frames, tiles and specs

- **Frames compute.** A frame is one SELECT, streamed to the browser as
  Arrow. URL parameters bind as placeholders (`$region` in the SQL,
  `?region=EMEA` in the URL); they arrive as text, so cast them. The
  dataset comes from the path, and `current_dataset` names it. A frame
  can read anything a query can: a metric by its name,
  `metric_series()` for a metric at a grain, `band_points()` for the
  expected ranges. Labels, percentages and CSS classes are columns the
  frame computes; templates only place values. `fmt_number()` and
  `fmt_change()` print numbers the way the console does.
- **Tiles place.** A tile shows what a frame computed: a value, a chart,
  a table, or rows with a template. Each tile carries a chip naming the
  view its number comes from. Clicking a chart puts the clicked value
  in the URL; that is all a drill does.
- **Specs draw.** A spec is Vega-Lite JSON over the frame's columns:
  encodings and marks. Filtering and aggregating belong in the frame,
  where they can be tested.

A page is markup, not code. Every page is served under a content
security policy that runs the console's own scripts and nothing the
page carries.

## The console and your apps

The console is the app that ships in the binary ([the console](console.md)).
To show something else, write your own app beside it; a workspace can
hold as many as it needs. A part annotated under the console's name is
refused, so the console keeps all its pages.

Apps only read. The only writes a browser makes are the console's two:
answering a question and re-measuring. To change anything else, send a
statement.
