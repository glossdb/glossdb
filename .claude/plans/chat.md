# Chat plan

How a result reaches a person inside the chat, and how their review
decision gets back. There are two ways. Which one people and agents
use well is not measured, so this plan is an experiment with one
measure, not a build list. Today the agent writes a link to the
console and the person follows it. The trial itself is `clients.md`.

| Option | Cheapest build that tests it | Effort |
|---|---|---|
| A page beside the chat | an `open:` line on the result, built from `own_uri`, one page per result, absent when nothing waits on the person; a paragraph in the skill: open it where the client has a browser beside the chat, give the link elsewhere, never fill the form | half a day |
| A card under the tool call | `structuredContent` on the result; `_meta.ui.resourceUri` on the `glossql` tool naming one `ui://` page that shows the open questions and links the console (#20) | one to two days |

## The two options

**A page beside the chat.** The result names a console page when
something waits on the person: a question to decide, files to add.
The agent opens it. In Cowork the page opens in a pane beside the
chat and stays signed in. In claude.ai, Claude Desktop's chat, Claude
for Excel and ChatGPT the same link opens the browser. The page
stores the decision as the person's. A stream keeps the page current
while the agent works.

**A card under the tool call.** The MCP Apps standard: a tool's
listing names a `ui://` HTML resource in `_meta.ui.resourceUri`; the
host renders it in a sandboxed frame under the call and gives it the
result's `structuredContent`. Claude on web, desktop, mobile and
Cowork, and ChatGPT render it; Claude Code does not. Limits:

- A card appears only when the model calls the tool. The server
  cannot push one, and the standard says nothing about replacing an
  earlier card.
- A click in a card reaches the server as a tool call by the agent.
  So a decision made in a card is still a link to the page.
- A card holds four or five values and two actions. A result over
  about 150,000 characters never reaches it.

## What is there

- Every result ends with `status:` and `next:`
  (`crates/serverd/src/window.rs`). `next:` carries `next://` links
  for the model and nothing a person can open. The MCP endpoint does
  not know the server's address: `own_uri` reaches the console's
  routers (`crates/serverd/src/lib.rs`) and not the MCP code.
- The question forms render in Claude Code and not in claude.ai. The
  server skips them when the client lacks the capability
  (`question_round` in `mcp.rs`), and the questions reach the person
  as text. The model cannot record an answer: what arrives over MCP
  is stored as the agent's, and SPEC.md §1 keeps an agent from
  answering as a person.
- The console stores a decision as the person's, by cookie
  (`crates/apps/src/rule.rs`). A page refreshes only after its own
  write (`HX-Trigger: glossql:written`, and `glossql:remeasured` from
  `remeasure.rs`). The catalog's version changes on any write;
  nothing notifies on it. The page's security policy allows a
  same-origin stream (`pages.rs`).
- Results carry no `structuredContent`. The MCP library in use has
  the fields (rmcp).
- glossval logs every call of every scored session, so pages or cards
  per question is a query over its log.
- In Cowork the agent can fill the decision form with the person's
  cookie, and the server cannot tell that click from the person's.
  Accepted for the trial; the skill says to hand over.

## The experiment

One measure for both options, on scored sessions, on Sonnet and a GPT
model: does the agent put the page or card in front of the person
when something waits and not otherwise, and is the decision stored?
Counted: calls per session, pages or cards opened per open question,
unneeded opens, decisions stored.

The winner is built out after the measure.

- **Page:** a server-sent event stream on the console (`GET
  /<dataset>/app/events`, events `written` and `remeasured`, a
  listener on the page; one to two days), and a tile that shows the
  `next` view (half a day to a day).
- **Card:** the hosts' design rules, what a repeated call does to
  earlier cards, a drop zone with a signed upload link.

## For the lead to decide

- Whether to test the card at all, or the page alone.
- The long-term answer to the agent filling the form in Cowork.

## Sources

- MCP Apps: https://modelcontextprotocol.io/extensions/apps/overview
- Claude's design rules and the character cap:
  https://claude.com/docs/connectors/building/mcp-apps/design-guidelines,
  https://claude.com/docs/connectors/building/mcp-apps/troubleshooting
- ChatGPT's UI layer: https://developers.openai.com/plugins/build/chatgpt-ui
- The browser beside the chat:
  https://support.claude.com/en/articles/16607400-use-the-built-in-browser-in-claude-cowork
- Forms per Claude surface:
  https://help.relativity.com/RelativityOne/Content/Relativity/MCP/Anthropic_Claude.htm
