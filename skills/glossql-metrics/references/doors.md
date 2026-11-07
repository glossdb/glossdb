# The other doors — read for a bespoke function or an app

## Author what is missing

**A function** when a shipped measurement does not fit this dataset's
shape — and the measuring half of a validation, which the expectation
annotation needs (`skill://glossql-metrics/references/validate.md`).
**`glossql-functions` teaches it**: the declaration carries the body,
so an agent can write a check over MCP, and the shipped library reads
back as worked examples
(`SELECT script FROM functions WHERE name = 'rate_tolerance'`). The
short version: a measurement's body is one SQL query the engine plans,
a function without `RETURNS` is a detector (a script over the values
collected for an aspect, `slots`), and a function abstains
(`applicable: false` with a reason) rather than throwing.

**An app** when someone needs to look at this — a standalone page at
`/<dataset>/app/<name>` whose URL is its whole state, so a filtered
view is a link somebody can send. **`glossql-apps` teaches it**: shape
it with the user in prose first, then write it as annotations (`app`,
`app_page`, `app_frame`, `app_spec`, one per part). Add an app beside
the console rather than forking it. Frames are SQL and display logic is
computed there, never in a template; an app you author carries no
write.
