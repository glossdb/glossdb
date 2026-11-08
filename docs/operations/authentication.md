# Authentication

glossdb signs people and agents in through your identity provider.
It is an OAuth 2.1 resource server: it verifies tokens against the
keys your provider publishes. It issues no tokens and keeps no user
table.

## Set up the provider

Any OpenID Connect provider works.

1. Register this server as an API whose identifier is
   `GLOSSDB_AUDIENCE`.
2. Register one confidential application (`GLOSSDB_CLIENT_ID`,
   `GLOSSDB_CLIENT_SECRET`) with two redirect URIs:
   `<audience>/auth/callback` for the browser sign-in, and the loopback
   redirect of the MCP client that signs in with it (Claude Code:
   `http://localhost:3118/callback`, see
   [connect](../getting-started/connect.md)).
3. Set `GLOSSDB_ISSUER` to the provider's issuer URL. Its discovery
   document (`<issuer>/.well-known/openid-configuration`) is everything
   the server needs.

Tokens must be RS256, ES256/384 or EdDSA, name their key (`kid`), and
carry `iss`, `sub` and `exp`.

A token is bound to this server by its `aud` naming the audience. MCP
clients ask for that with the RFC 8707 `resource` parameter, so the
provider must honour it: register the audience as a resource the
provider can mint tokens for. The server refuses a token that names
another resource, or none.

A request without a valid token gets a 401, and a server without an
issuer does not start. The one exception is
`GLOSSDB_INSECURE_OPEN=true`, which serves every interface without
sign-in and records every caller as `insecure_dev_mode`: for a laptop,
never a deployment.

## Actors

The token's subject is the actor: who wrote a value. The interface
sets the actor's kind: the MCP interfaces write as an agent, the
console and the query endpoint as a person. An agent's id is the
token's subject, never the name its client gives itself.

Authorship comes from the connection, not from the statement: no
statement can claim to be someone else. A person who answers a
review question in the agent's client writes as a person too; the
server records the answer with that person's standing.

## Which value wins

Values are never updated in place. Every write appends, and the
current value is a read: the newest row per (asset, aspect, actor
kind). A person's new value replaces the person's earlier one; an
agent's replaces the agent's.

The agent's value, the person's value and each measurement stay side
by side. `GLOSSARY()` serves one value per asset and aspect, by
precedence: **person over agent over measurement**. It withholds the
value only when a test scores the disagreement above its threshold;
the state is then `contested`, with the band and score saying how
badly. A person's decision outranks the agent without deleting
anything: the agent's value stays, visible in the full read:

```glossql
SELECT * FROM GLOSSARY(orders.amount, all => true);
```

The full read returns every value side by side,
`(subject, aspect, kind, test, actor, body, written_at, current)`;
`current` is false for a measurement made on data that has since
changed.

This gives you:

- **Corrections without ceremony.** One person's correction is one
  `GLOSS`; every view that uses the aspect serves the new value from
  then on.
- **An audit trail in the data.** Who said what, as which kind, when:
  every row carries it.
- **No agent can write as a person.** Only a person's sign-in writes a
  person's value.

The normative definition: [SPEC.md §1, §5.2](https://github.com/glossdb/glossql/blob/main/SPEC.md).

## Engine settings

`SET`, `ATTACH`, `INSTALL`, `LOAD` and `CALL` are open only to the
actor ids `GLOSSDB_ROOT` names ([configuration](configuration.md)).
