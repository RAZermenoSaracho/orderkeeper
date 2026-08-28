# API Conventions — `order-indexer`

## Routes

Implemented:

```
GET /orders    # list orders, optional ?status=pending|executed|cancelled
```

`GET /orders/:id` and owner/pagination filtering are not implemented yet —
`GET /orders` is scoped narrowly to what `keeper-bot` needs (see
`.claude/skills/deploy/` era decisions and CLAUDE.md); the broader read
surface waits for the frontend task that actually needs it. `:id` will be
the on-chain order id (`uint256`, same as the `orderId` field already
returned by `GET /orders`), not a separate indexer-assigned id, once added.

## Response shape

```json
{
  "data": [ { "...": "..." } ],
  "meta": { "count": 0 }
}
```

- List responses: `{ "data": [ ...orders ], "meta": { "count": N } }`.
  Single-resource responses (`GET /orders/:id`, not yet implemented) will
  follow `{ "data": { ...order } }` when added.
- Field naming: `camelCase` in JSON, matching TS conventions elsewhere in
  the stack.
- `uint256`/`Decimal` on-chain values (`targetPrice`, `amount`,
  `executionPrice`, `keeperFee`, `amountOut`) are serialized as **strings**,
  not numbers — they routinely exceed JS's safe integer range. Block
  numbers (`createdAtBlock`, etc.) are strings for the same reason.
  `expiry` is an ISO 8601 string.

## Error format

```json
{
  "error": {
    "code": "INVALID_STATUS",
    "message": "status must be one of: pending, executed, cancelled"
  }
}
```

- HTTP status codes used conventionally (`400` for bad input; `404`/`500`
  apply once routes that can hit them exist).
- `code` is a stable, machine-readable string; `message` is human-readable
  and not relied upon by clients for logic.

## Rate Limiting

`GET /orders` is rate-limited per IP via `@fastify/rate-limit`: 100
requests/minute by default (`RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW_MS`,
see `.env.example`) — chosen to comfortably cover several open frontend
tabs and multiple keeper-bot instances polling normally, while still
bounding scripted abuse. `/health` is deliberately excluded, so uptime
monitoring never competes with real traffic for the same budget. Exceeding
the limit returns `429`, reformatted by the shared `setErrorHandler` into
the standard `{error:{code:"RATE_LIMIT_EXCEEDED", message}}` shape rather
than the plugin's raw default response body.

## Not yet decided

- Auth (if any) for read access — currently a fully public, read-only API
  per `CLAUDE.md`, but this hasn't been explicitly confirmed.
- Versioning strategy (`/v1/...` prefix vs none).
