# 19 · A what-if scenario on a price

A sales team asks what revenue would do if list prices rose. The
price is a lever: a column of the metric's view that someone sets. A
scenario is a property of its own on the dataset, with a factor per
period on declared levers. The outlook kit (preview) reads it and
serves the estimate as a world of `metric_series()`.

## The lever

```glossql
USE sales;

GLOSS lever ON revenue.unit_price AS $${
  "value": true, "basis": "the list price, set by sales operations each quarter"
}$$;
GLOSS lever ON revenue.units AS $${
  "value": false, "basis": "demand: nobody sets it"
}$$;
```

## The scenario's declaration

```glossql
DECLARE ASPECT price_hike WITH $${
  "title": "Prices up 15% from January",
  "description": "List prices raised 15% across the board",
  "x-kind": "scenario",
  "type": "object",
  "required": ["levers"],
  "properties": {"levers": {"type": "array", "items": {
    "type": "object",
    "required": ["column", "factor", "basis"],
    "properties": {
      "column": {"type": "string"},
      "factor": {"type": "object", "additionalProperties": {"type": "number"}},
      "basis":  {"type": "string"}
    }
  }}}
}$$ AS FACT ON DATASET;
```

## The factors

```glossql
GLOSS price_hike ON sales AS $${
  "levers": [
    {"column": "revenue.unit_price",
     "factor": {"2027-01": 1.15, "2027-02": 1.15, "2027-03": 1.15,
                "2027-04": 1.15, "2027-05": 1.15, "2027-06": 1.15},
     "basis": "the price list the board approved"}
  ]
}$$;
```

## The reads

```glossql
SELECT metric, period, value FROM metric_series(world := 'scenario', scenario := 'price_hike');
SELECT period, pass, value, low, high, held_80, held_from, sign, basis
FROM scenario_points('price_hike') WHERE metric = 'revenue';
```

## Who may write the scenario

```glossql
DECLARE TEST scenario_gate ON price_hike BY (HUMAN);

GLOSS price_hike ON sales AS $${
  "levers": [
    {"column": "revenue.unit_price",
     "factor": {"2027-01": 1.10, "2027-02": 1.10, "2027-03": 1.10},
     "basis": "revised down after review"}
  ]
}$$;
```
