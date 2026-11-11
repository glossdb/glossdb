# Quickstart

Two CSV files go in. A tested table, a single value and a metric come
out. The session takes the five steps: connect, describe, test,
decide, serve. An agent normally sends these statements over MCP; here
you send them yourself, so each step is visible.

You need a running server with sign-in off
([installation](installation.md)), `curl` and `jq`.

## The data

```bash
mkdir -p ~/shop/exports && cd ~/shop
cat > exports/customers.csv <<'EOF'
customer_id,name,region
C1,Alder Cafe,north
C2,Birch Hotel,north
C3,Cedar Foods,south
C4,Dune Market,south
EOF
cat > exports/orders.csv <<'EOF'
order_id,customer_id,ordered,amount,status
O01,C1,06.01.2025,120.00,shipped
O02,C3,20.01.2025,80.50,shipped
O03,C2,03.02.2025,210.00,shipped
O04,C4,17.02.2025,N/A,cancelled
O05,C1,04.03.2025,95.00,shipped
O06,C3,18.03.2025,130.25,shipped
O07,C2,02.04.2025,60.00,shipped
O08,C4,15.04.2025,175.00,shipped
O09,C1,05.05.2025,140.00,shipped
O10,C9,19.05.2025,99.00,shipped
O11,C3,03.06.2025,220.00,shipped
O12,C2,16.06.2025,45.75,cancelled
EOF
```

The files hold three defects on purpose: dates as text, an `N/A`
amount, and an order for a customer `C9` that the customer file does
not hold.

## A helper

The MCP interface has one tool, `glossql`. This function sends a file
of statements to it as an agent would and prints the result:

```bash
gq() {
  jq -Rs '{jsonrpc: "2.0", id: 1, method: "tools/call",
           params: {name: "glossql", arguments: {statements: .}}}' "$1" |
  curl -s "http://127.0.0.1:8080/${2:-mcp}" -d @- \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' |
  jq -r '.result.content[].text'
}
```

Save each block below as a file and run it: `gq 1-connect.sql` for the
workspace, `gq 2-load.sql shop/mcp` once the dataset exists.

## 1. Connect

Declare the source and the dataset, then look before loading. A dry
run (`PREVIEW`) runs SQL at the source and loads nothing; `LIMIT 0`
returns the columns.

```glossql
DECLARE SOURCE shop_export SET (type: csv, location: '/home/me/shop/exports');
DECLARE DATASET shop SET (purpose: 'order intake: what is ordered, by whom, for how much');
PREVIEW shop_export AS $$SELECT file FROM glob('*') ORDER BY file$$;
PREVIEW shop_export AS $$SELECT * FROM read_csv('orders.csv', all_varchar = true,
  nullstr = null_markers(), store_rejects = true) LIMIT 0$$;
```

Use the absolute path of your `exports` directory as the location.

A load query (`DECLARE RECIPE`) brings a table into the dataset. A CSV
file has no types, so its reader gets one standard configuration and
the load query carries the casts:

```glossql
DECLARE RECIPE customers ON shop FROM shop_export AS $$
  SELECT trim(customer_id) AS customer_id, name, region
  FROM read_csv('customers.csv', all_varchar = true,
                nullstr = null_markers(), store_rejects = true)$$;

DECLARE RECIPE orders ON shop FROM shop_export AS $$
  SELECT trim(order_id) AS order_id,
         trim(customer_id) AS customer_id,
         try_strptime(ordered, '%d.%m.%Y')::DATE AS ordered,
         try_cast(amount AS DOUBLE) AS amount,
         status
  FROM read_csv('orders.csv', all_varchar = true,
                nullstr = null_markers(), store_rejects = true)$$;
```

```
[{"done":"loaded shop.customers: 4 rows, 0 dropped (new)"},
 {"done":"loaded shop.orders: 12 rows, 0 dropped (new)"}]
status: done
```

`N/A` is one of the strings `null_markers()` lists, so that amount is
NULL.

## 2. Describe

Annotate (`GLOSS`) what a row is and what the amount means. Declare
the join. Then measure how well the join holds.

```glossql
GLOSS entity ON orders AS $${"value": "one row per order", "role": "fact",
  "identity_columns": ["order_id"], "time_axis": "ordered"}$$;
GLOSS meaning ON orders.amount AS $${"value": "order value net of tax"}$$;
GLOSS role ON orders.amount AS $${"value": "measure"}$$;
GLOSS unit ON orders.amount AS $${"value": "EUR"}$$;
GLOSS additivity ON orders.amount AS $${"value": "additive", "basis": "one amount per order"}$$;

DECLARE RELATIONSHIP orders.customer_id -> customers.customer_id;
SELECT relationship_coherence() FROM shop;
```

The measurement finds the defect: 1 of 12 orders has no customer
(`"orphans":1,"orphan_rate":0.0833…`). Each result now ends with the
open work:

```
next: serve 1
first: serve shop (missing): no view is defined (a table, a single value or a metric) (next://shop/serve)
```

## 3. Define three views

A view is named SQL on the dataset. Declare the name (`AS VIEW`), then
annotate it with its SQL.

```glossql
DECLARE ASPECT shipped_orders WITH $${"title": "Shipped orders", "x-kind": "relation"}$$ AS VIEW;
GLOSS shipped_orders ON shop AS $${
  "sql": "SELECT o.order_id, o.ordered, o.amount, c.region FROM orders o JOIN customers c ON c.customer_id = o.customer_id WHERE o.status = 'shipped'",
  "assumptions": [
    {"dimension": "scope", "key": "shipped-only", "assumption": "cancelled orders are left out",
     "basis": "the status column holds shipped and cancelled", "confidence": 0.7}
  ]
}$$;

DECLARE ASPECT customer_count WITH $${"title": "Customers", "x-kind": "scalar"}$$ AS VIEW;
GLOSS customer_count ON shop AS $${"sql": "SELECT count(*) AS value FROM customers"}$$;

DECLARE ASPECT order_value WITH $${"title": "Order value"}$$ AS VIEW;
GLOSS order_value ON shop AS $${
  "sql": "SELECT ordered, amount AS value, region FROM shipped_orders",
  "time": "ordered",
  "measure": {"column": "value", "additivity": "additive", "unit": "EUR"},
  "dimensions": ["region"]
}$$;
GLOSS time_grains ON order_value.ordered AS $${"floor": "month", "basis": "orders are reported by month"}$$;
```

- `shipped_orders` is a table (`x-kind: relation`). Its definition
  states one assumption below full confidence, for a person to confirm.
- `customer_count` is a single value (`x-kind: scalar`): one row, one
  `value` column.
- `order_value` is a metric: a value per period, sliced by region. It
  builds on `shipped_orders`. The order dates follow no regular grain,
  so `time_grains` states the grain the series is served at.

## 4. Serve

All three read like tables. The metric also has a series:

```sql
SELECT region, count(*) AS orders, sum(amount) AS amount
FROM shop.shipped_orders GROUP BY region ORDER BY region;
```

```sql
FROM shop.customer_count;
```

```sql
SELECT period, value FROM metric_series()
WHERE metric = 'order_value' AND dimension = '' ORDER BY period;
```

The table returns 5 orders and 625.00 for north, 4 and 605.75 for
south. The single value returns 4. The series returns one row per
month, January to June: 200.5, 210, 225.25, 235, 140, 220.

## 5. Test

The server ran the built-in tests when the metric was defined. One is
red, and `next` puts it first:

```
next: describe 5 · test 1 · waiting for a person 1
first: test shop.order_value (red): orphan_test: 8.3% of rows on shop.orders.customer_id -> shop.customers.customer_id find no parent: an inner join drops them, an outer join counts them under no member (next://shop/test)
```

Order `O10` is missing from May: the inner join dropped it. Each test
with its state:

```sql
SELECT test, subject, state, score FROM view_tests();
```

`orphan_test` is red; `fan_out_test`, `measure_additivity_test` and
`validity_test` are green. The `statement` column of `next` carries
the fix: repair the load, or accept the rate with a reason.

## 6. Decide

Two things wait for a person: the red test, and the assumption in
`shipped_orders`. A person answers in the console
(`http://127.0.0.1:8080/shop/app`) or with statements over the query
endpoint, which writes as a person:

```glossql
GLOSS orphan_check ON shop.order_value AS $${"tolerance": 0.1,
  "basis": "C9 is a walk-in customer without a master record"}$$;
GLOSS review_decision ON shop AS $${"decisions": [
  {"aspect": "shipped_orders", "key": "shipped-only", "stance": "confirmed",
   "note": "cancelled orders are not revenue"}]}$$;
```

```bash
curl -s -X POST --data-binary @6-decide.sql http://127.0.0.1:8080/shop/query
```

The test is green at the accepted rate, with the reason stored. The
decision goes back to the agent as a row of `next`:

```
decide shop.shipped_orders (decided): a person decided shipped-only (confirmed): cancelled orders are not revenue; the definition does not carry it yet
```

The agent records the definition again with that assumption at
confidence 1.0, and the row closes. What remains in `next` is the
describe step: the columns nobody annotated yet.

## Where next

- Each step in depth: [connect and load](../usage/load.md),
  [describe](../usage/describe.md), [define views](../usage/views.md),
  [test](../usage/test.md), [review and decide](../usage/review.md),
  [serve and read](../usage/serve.md).
- Let an agent do the work: connect one
  ([installation](installation.md#connect-an-agent)) and ask it to
  load a folder and describe it. The skills it reads are served by the
  server.
