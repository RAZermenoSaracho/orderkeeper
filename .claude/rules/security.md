# Security — Non-Negotiable Rules

This file exists for exactly two rules. Both apply to every component in
this repo (`contracts/`, `order-indexer/`, `keeper-bot/`, `frontend/`)
without exception, and neither is a matter of judgment or context — they
apply every time, in every file, regardless of what else is being asked.

## (a) Never hardcode secrets

Never hardcode secrets, API keys, private keys, or RPC URLs with embedded
keys — anywhere: in code, scripts, config files, test fixtures, or commit
messages.

Every secret must be read from an environment variable, sourced from a
`.env` file:

- `.env` is documented (what variables exist, what they're for) but
  **never committed** — it's already covered by `.gitignore`.
- A corresponding `.env.example` (committed) lists the variable names with
  placeholder or empty values, never real ones.
- This includes RPC URLs that embed a provider API key (e.g. an Alchemy or
  Infura URL with a key in the path/query) — those are secrets too, not
  just endpoints.
- This includes MCP server configs (`.mcp.json`) — env values there must be
  references like `${VAR_NAME}`, never literal tokens. See
  `.mcp.json.example`.

If you (the agent) are about to write a literal-looking secret into any
file that isn't `.env` or a local, gitignored file — stop and use an
environment variable reference instead.

The hook at `.claude/hooks/validate-bash.sh` scans staged changes for
obvious hardcoded-secret patterns and blocks the operation if it finds one.
It is a backstop, not a substitute for not doing this in the first place —
it will not catch every pattern.

## (b) English only, always

All output — code, comments, NatSpec, identifiers, commit messages,
documentation, everything written into this repo — is written 100% in
English, with no exceptions, regardless of the language used in the
conversation that produced it.

This is absolute, not stylistic: it applies even if the user writes to the
agent in another language, and even for content (like a code comment or
commit message) that only the two of you might ever read.
