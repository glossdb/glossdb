# The console

The console is where people work with a dataset in the browser: answer
the agent's questions, read the metrics, check the data's quality, and
look up what is known about any table or column. It opens at
`/<dataset>/app` and ships in the binary.

## Find your way

The bar at the top has a dataset picker, an app picker (the console,
and any [data apps](data-apps.md) the workspace holds), and six
sections: Overview, Catalog, Metrics, Quality, Review and Data. The
list on the left shows what is inside the current section:

| Section | The left list |
|---|---|
| Overview | the scorecard, the model, the history, lineage |
| Catalog | the properties, each source, each table with its columns, each view |
| Metrics | each metric, then each single value |
| Quality | all results, then each test |
| Review | the queue, the decisions |
| Data | export, query |

A table, column, source or view opens in Catalog, a metric in Metrics,
a test in Quality. The breadcrumb above each page names the way back,
e.g. `hr › Catalog › Tables › employees`. Every view's state is in the
URL, so you can send any view as a link.

Each section has a plain name; hover over it for what it shows.
**Show queries** in the bar adds the view or function each section
reads, such as `metric_series()`, so you can run the same query
yourself. The browser remembers the choice.

## Review

The open questions, the decisions taken, and what waits for an action.

To answer a question:

1. Read the assumption, its confidence, its basis and, where the agent
   named one, the alternative reading.
2. Choose **Correct as stated**, or open **Correct it** and write the
   correction in your own words.
3. The answer is stored as your annotation and outranks the agent's.
   The question leaves the queue, and the agent is asked to apply the
   decision.

The same questions reach the agent's client as forms
([the review queue](review.md)). **Waiting for an action** lists what
an agent still has to do, such as a measurement never run or a
decision not yet applied.

## Metrics

Every metric, view and single value, with its latest value and change.
Open a metric for its page:

- **The story**: the series as a chart, at the grain and window you
  pick (day to year; 12, 24 or all periods);
- **The plan** beside it, and the forecast (preview);
- **What moved**: the members that moved most between the last two
  periods;
- **Slice**: the metric by one dimension;
- **Why these axes**: the grain, window, additivity and slices the
  metric is served at, and what it still needs;
- **The assumptions behind it**, decided or still open;
- **The stored result**: the SQL that runs.

**Re-measure** runs again every measurement made before the last change
to the data. It shows when one is due.

## Quality

The tests and their results, worst first; findings from loads and
measurements; columns where annotations disagree; expectations against
what was measured; each table's loads, with the rows dropped and the
values the casts turned to NULL; and what is required but not yet
annotated.

## Glossary

What is known about every table, column, join, source and property.
Each table has a page with its columns, joins, identities among its
columns and its latest load. Each column has a page with every value
written about it, by whom and when. **The harness schema** lists every
declared property, and **Terms** the business terms with their
meaning.

## Lineage

The loaded tables on the left, along their declared keys, and the
metrics they feed on the right. Hover a column to follow it; click to
put it in the URL. When the graph is wider than the page, scroll right
for the metrics.

## Export and Query

**Export** downloads every table and every metric as CSV or Parquet.
**Query** runs a read of your own against the dataset, with the views
and tables you can query listed beside it.

## What the console writes

The console only reads, with two exceptions: answering a question and
re-measuring. Everything else is changed with a statement, by an agent
or over the query endpoint ([querying and export](querying.md)).
