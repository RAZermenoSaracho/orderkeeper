# API Conventions — `order-indexer`

**DRAFT, confirm with Ricardo.** Nothing in this file has been implemented
or agreed on yet — `order-indexer` doesn't exist as code. These are
reasonable defaults to start a discussion, not decisions.

## Routes

DRAFT, confirm with Ricardo — matches the two routes named in `CLAUDE.md`:

```
GET /orders          # list orders, optionally filtered
GET /orders/:id       # single order by id
```

Open questions (DRAFT):
- Query params for `GET /orders` — filter by owner address? by status
  (pending/executed/cancelled)? pagination (`?limit=&cursor=`)?
- Is `:id` the on-chain order id (uint), or an indexer-assigned id?

## Response shape

DRAFT, confirm with Ricardo:

```json
{
  "data": { "...": "..." },
  "meta": { "...": "..." }
}
```

- Single-resource responses: `{ "data": { ...order } }`
- List responses: `{ "data": [ ...orders ], "meta": { "count": 0 } }`
- Field naming: `camelCase` in JSON, matching TS conventions elsewhere in
  the stack.

## Error format

DRAFT, confirm with Ricardo:

```json
{
  "error": {
    "code": "ORDER_NOT_FOUND",
    "message": "No order with id 123"
  }
}
```

- HTTP status codes used conventionally (`404` for not found, `400` for bad
  input, `500` for unexpected server errors).
- `code` is a stable, machine-readable string; `message` is human-readable
  and not relied upon by clients for logic.

## Not yet decided

- Auth (if any) for read access — currently the plan is a fully public,
  read-only API per `CLAUDE.md`, but this hasn't been explicitly confirmed.
- Rate limiting.
- Versioning strategy (`/v1/...` prefix vs none).
