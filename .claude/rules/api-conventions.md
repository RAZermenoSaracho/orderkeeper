# API Conventions — `order-indexer`

## Routes

Implemented:

```
GET /orders    # list orders, optional ?status=... and/or ?owner=0x...
```

`owner` is validated as an Ethereum address and matched case-insensitively.
It scopes the frontend's "My Orders" UX to the connected wallet; it is not
authentication or privacy, because indexed blockchain data is public.

`GET /orders/:id` and pagination filtering are not implemented yet —
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
- `side` is `"Sell"` or `"Buy"`, and determines how `amount` is
  denominated: wei for Sell orders (which deposit ETH), quoteToken base
  units for Buy orders. Clients must not assume a single denomination.
  It replaced the former `asset` field when orders became bidirectional
  trades of one fixed pair rather than single-direction trades tagged with
  a price-trigger asset.
- `uint256`/`Decimal` on-chain values (`targetPrice`, `amount`,
  `executionPrice`, `keeperFee`, `amountOut`) are serialized as **strings**,
  not numbers — they routinely exceed JS's safe integer range. Block
  numbers (`createdAtBlock`, etc.) are strings for the same reason.
  `expiry` is an ISO 8601 string.
- Amount and price fields use `NUMERIC(78,0)` and therefore preserve the full
  uint256 integer domain exactly. The practical MVP application domain keeps
  `orderId` within PostgreSQL `INTEGER` and `expiry` within JavaScript's Date
  range. The indexer rejects unsupported values and does not advance its
  checkpoint; it never truncates or stores a corrupted approximation.

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
- Invalid `owner` values return `400` with code `INVALID_OWNER`.
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
