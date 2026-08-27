import { createPublicClient, http, webSocket } from "viem";
import { sepolia } from "viem/chains";

const rpcUrl = process.env.RPC_URL;
if (!rpcUrl) {
  throw new Error("RPC_URL is not set");
}

// viem already retries HTTP 429s with exponential backoff by default
// (~~(1 << count) * retryDelay, respecting a Retry-After header if the
// provider sends one) — but its defaults (retryCount: 3, retryDelay: 150ms)
// only buy ~1s of total backoff, which isn't enough headroom against a
// free-tier rate limit during backfill's thousands of sequential
// eth_getLogs calls (see indexer.ts's backfill()). Raised here rather than
// reimplementing retry logic: retryCount: 5, retryDelay: 500ms bases out at
// 500/1000/2000/4000/8000ms between attempts, ~15.5s of cumulative backoff
// before a single call gives up.
const retryOptions = { retryCount: 5, retryDelay: 500 };

// Without this, a 429 being retried internally by viem is invisible —
// nothing logs until either the request finally succeeds or all retries
// are exhausted, which during a large backfill can look identical to a
// hang for many minutes at a time.
function onFetchResponse(response: Response): void {
  if (!response.ok) {
    console.warn(`RPC request failed: HTTP ${response.status} ${response.statusText} — retrying...`);
  }
}

// CLAUDE.md documents RPC_URL as "WebSocket-capable" for order-indexer —
// use a real WS subscription (push-based, lower latency) when given one,
// falling back to HTTP (viem's built-in polling) otherwise so a plain
// https:// URL still works. onFetchResponse only applies to the HTTP
// path — a WS connection has no per-request HTTP response to hook into.
const transport =
  rpcUrl.startsWith("ws://") || rpcUrl.startsWith("wss://")
    ? webSocket(rpcUrl, retryOptions)
    : http(rpcUrl, { ...retryOptions, onFetchResponse });

export const publicClient = createPublicClient({
  chain: sepolia,
  transport,
});
