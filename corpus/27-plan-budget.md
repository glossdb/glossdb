# 27 · A budget beside its actuals

A city's expense table carries the month's actual spend and two
budgets on each row: the adopted budget, booked in January, and the
revised budget, with each amendment booked in its month. The actual
is a metric. Each budget is a plan: a view of its own that names the
metric it plans. The outlook kit (preview) serves a plan as a world of
`metric_series()`.

## The metric

```glossql
USE city;

GLOSS meaning ON expense_budget.actual AS $${
  "value": "the month's expenditure on the account; twelve months sum to the year's spend"
}$$;
GLOSS meaning ON expense_budget.revisedbudget AS $${
  "value": "budget authority booked in the month: the adopted budget on the January row, each amendment on the row of its month"
}$$;
GLOSS conventions ON budget_export AS $${
  "fiscal_year": "the calendar year",
  "budget_booking": "the adopted budget is booked in January; an amendment in the month it was approved, as a delta",
  "sign": "expenditures positive; a negative actual is a reversal"
}$$;

DECLARE ASPECT expense WITH $${"title": "Operating expense"}$$ AS VIEW;

GLOSS expense ON city AS $${
  "sql": "SELECT fiscalmonth, actual AS value, fund, department FROM expense_budget",
  "time": "fiscalmonth",
  "measure": {"column": "value", "additivity": "additive", "unit": "USD"},
  "dimensions": ["fund", "department"],
  "assumptions": [
    {"dimension": "grain", "key": "monthly-actual", "assumption": "actual is the month's amount, not the year to date",
     "basis": "a year's twelve months sum to its budget", "confidence": 0.95},
    {"dimension": "scope", "key": "closed-accounts", "assumption": "closed and inactive accounts keep their rows",
     "basis": "accountstatus", "confidence": 1.0}
  ]
}$$;
```

## The plans

```glossql
DECLARE ASPECT revised_budget WITH $${
  "title": "Revised budget",
  "description": "The adopted budget with its amendments, as booked",
  "x-kind": "plan", "x-plan-of": "expense", "x-covers": "year"
}$$ AS VIEW;

GLOSS revised_budget ON city AS $${
  "sql": "SELECT fiscalmonth, revisedbudget AS value, fund, department FROM expense_budget",
  "assumptions": [
    {"dimension": "grain", "key": "booked-against-year", "assumption": "a year's budget: the adopted figure in January, each amendment in its month",
     "basis": "the rows", "confidence": 0.95}
  ]
}$$;

DECLARE ASPECT original_budget WITH $${
  "title": "Original budget",
  "description": "The budget as adopted",
  "x-kind": "plan", "x-plan-of": "expense", "x-covers": "year"
}$$ AS VIEW;

GLOSS original_budget ON city AS $${
  "sql": "SELECT fiscalmonth, originalbudget AS value, fund, department FROM expense_budget"
}$$;
```

## Who may write the plan

```glossql
DECLARE TEST plan_gate ON revised_budget BY (HUMAN);
```

## The reads

```glossql
SELECT metric, period, value FROM metric_series(world := 'plan', plan := 'revised_budget', grain := 'year');

SELECT a.period, a.value AS actual, p.value AS plan, a.value - p.value AS variance
FROM metric_series(grain := 'year') a
JOIN metric_series(world := 'plan', plan := 'revised_budget', grain := 'year') p
  ON a.metric = p.metric AND a.period = p.period
WHERE a.metric = 'expense' AND a.dimension = '' AND p.dimension = '';
```
