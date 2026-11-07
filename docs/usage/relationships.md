# Relationships

A relationship is a declared join between columns. It has no name: its
pair path addresses it, and the path is an asset you can annotate,
measure and test like a table or a column.

## Declare a relationship

```glossql
DECLARE RELATIONSHIP orders.customer_id -> customers.id;
DECLARE RELATIONSHIP invoices.order_id <-> orders.id;
DECLARE RELATIONSHIP txn.(business_id, account) -> coa.(business_id, code);
```

- `->` is many-to-one, written from the foreign-key side.
- `<->` is one-to-one.
- Many-to-many goes through a junction table, as two relationships.
- A composite key is a tuple of columns on each side.

Each end must name a column of a loaded table or view. A declaration
whose table or column is not in the dataset is refused, and the
refusal lists the tables, or the table's columns.

## Find candidates, verify, then declare

`detect_relationships()` proposes candidate joins with evidence: how
far one column's values are contained in another's. It proposes more
than are true, on purpose. Verify each candidate against the data
before you declare it:

- Run an anti-join in both directions. Orphans that are exactly a
  business population (cancelled orders, say) confirm a join; random
  misses argue against it.
- Count rows before and after the join. The counts must be equal, or
  the join multiplies every number computed over it.

Declare only the joins that pass. A rejected candidate is simply not
declared; detection is deterministic, so it comes back the same and
adds nothing new. Record what you found as an annotation on the join:

```glossql
GLOSS fk_note ON orders.customer_id -> customers.id AS $${"value": "2% orphaned rows"}$$;
```

## Measure a declared join

`relationship_coherence()` measures what each declared join claims:

- the orphan rate, exactly, which also catches a single repeated
  invented key that a count of rare values misses;
- children dated before their parent, the trace a wrong pairing leaves.

No statistic over one column sees either on a high-cardinality key.

Other measurements read through declared joins: stock-or-flow evidence
reconciles across them, and the derivation tests follow them. A missing
true join costs the analyses that would have used it; a declared false
one corrupts them. That is why the verify step matters.
