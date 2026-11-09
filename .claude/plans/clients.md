# Trial plan

What a person does on the hosted trial: sign up, connect Claude or
ChatGPT, upload a file, work. How results reach the person inside
the chat is `chat.md`. What a file becomes once it is uploaded is
`sources.md`. The platform is `../glossdeploy/platform.md`; this plan
says what the server needs from it and in what order. Build order is
risk order.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Spike: one workspace reachable at its own hostname from Claude Desktop and ChatGPT, end to end | High: nothing is built, and every item is on platform.md's list to verify | glossdeploy: the Worker route, the WorkOS wildcards; here: the next row | First; one to two days | |
| Organization check and extra allowed hosts | Low | `crates/serverd/src/auth.rs`, `config.rs`, the installation page | With the spike; one day | drafted below |
| Registration: a stranger gets a workspace without us | Medium: the order of the sign-up events is unverified; creation takes minutes | glossdeploy: the admin page, cut down | After the spike; about five days | |
| Upload page in the console | Low: the object store and the person's writes exist | `crates/apps`, `crates/serverd` | After the spike; one to two days | |
| One shared connector address | Low once the spike works: the same Worker, routing by the token's organization instead of the hostname | glossdeploy; a second audience on the MCP endpoint | When the directory listing is near | |

## The spike

One workspace created by hand, behind one Cloudflare route on
`<name>.glossdb.com`, with the WorkOS wildcards set. Then, from Claude
Desktop and from ChatGPT: add the connector, sign in, run a session
with a streamed answer, start from a stopped instance, and sign in to
the console in the browser at the same name.

Record: the sign-in handshake end to end; the cold-start time against
each client's tool timeout; whether the Worker streams the MCP
session; whether creating the workspace at sign-up or on the first
call is cheaper. It decides the hostname approach (the Worker or
Cloud Run's domain mapping) and whether the trial can open at all.

## What is there

- **One process, one address.** A token must name the server's
  address as its audience (`crates/serverd/src/auth.rs`). The server
  answers its own hostname and loopback (`allowed_hosts` in
  `config.rs`). Behind the Cloudflare route the Host header is the
  run.app host, so the server needs more allowed hosts from the
  environment. `Claims` reads `sub` and `aud`, not the organization.
  With a wildcard audience over `*.glossdb.com`, anyone signed up
  could get a token for another workspace, so the server must refuse
  a token whose `org_id` is not the workspace's, for bearer tokens and
  cookies alike. Neither setting is in the code yet.
- **Connecting.** A connector is added by URL in Claude on every plan
  and in ChatGPT. Both register themselves with the identity
  provider. There is no deep link; the person pastes
  `https://<name>.glossdb.com/mcp`.
- **Registration.** The server has no user table; it verifies the
  identity provider's tokens. WorkOS AuthKit's hosted page does the
  sign-up. A sign-up creates a person, not an organization; the
  application creates the organization after the first sign-in. A
  workspace is a service, a bucket and a database, and takes two to
  four minutes to create. The events `user.created` and
  `organization.created` exist; their order on a fresh sign-up is
  unverified.
- **Files.** MCP carries no file bytes. In Claude an attached file
  goes to the model's sandbox, never to a tool. A file can be loaded
  once it sits under a location a `DECLARE SOURCE` names. The GCP
  deployment exports `gs://<bucket>/sources`; the server reaches the
  object store through httpfs with the warehouse credential; on a
  laptop it reads a directory. The console already takes a person's
  writes with their cookie (`crates/apps/src/rule.rs`,
  `remeasure.rs`). So the upload page is a console page with a drop
  zone and a PUT that streams into that location. It needs no signed
  URLs and works on every storage backend and on a laptop.
- **The first session** is about 30 tool calls and runs well from
  Claude and ChatGPT. There is no preparation job and no onboarding
  command.
- **Cold start.** The process starts in 0.24 s on the laptop. Cloud
  Run's part is unmeasured; the spike measures it.
- **Claude for Excel.** Connectors work the same in the Office
  add-ins. Where its links open is undocumented. Test it when the
  trial runs.

## The admin page, cut down

The platform creates the workspace, tells the person how to connect,
stops and deletes it, shows usage against the caps, and enforces the
caps on a cron. So: sign-up on the identity provider's hosted page;
one status page per workspace with its state, the connect lines for
Claude, ChatGPT and Excel, the console link, usage, stop and delete.
No upload page (the console has it), no import button (the agent
loads on the first prompt), no organization page. About half of
platform.md's Worker.

## For the lead to decide

- The cut of the admin page, above.
- Create the workspace at sign-up by webhook, or on the first call
  with a placeholder answer. The spike says which is cheaper.
- Whether the server declares the upload location as a source at
  start, so loading works before the first prompt.
- A size cap on an upload, if any.

## Issue, drafted

### Organization check and extra allowed hosts

- **What it buys.** A workspace behind a wildcard audience refuses
  tokens of other organizations, and the MCP endpoint answers behind
  a route whose Host is not the audience's.
- **What is there.** `Claims` reads `sub` and `aud`
  (`crates/serverd/src/auth.rs`); the audience check is one compare.
  The allowed hosts are loopback and the audience's host
  (`allowed_hosts` in `crates/serverd/src/config.rs`). The identity
  provider's tokens carry `org_id`. `GLOSSDB_ORGANIZATION` and
  `GLOSSDB_ALLOWED_HOSTS` are named in the platform design and not in
  the code.
- **Done when.** With `GLOSSDB_ORGANIZATION` set, the server refuses a
  token whose `org_id` differs and accepts one that matches, for
  bearer tokens and cookies alike; unset, nothing changes.
  `GLOSSDB_ALLOWED_HOSTS` adds hosts to the allowed set. The
  installation page names both. The suite asserts a refused token, an
  accepted token and a request on the extra host.

## For the other repositories

- **glossdeploy**: the spike, then the admin page, the Worker route
  and the WorkOS wildcards. The shared address later is the same
  Worker routing by the token's organization, with a placeholder
  answer while a workspace starts.
- **glossval**: nothing here.
