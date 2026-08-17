import { createPublicClient, http, webSocket } from "viem";
import { sepolia } from "viem/chains";

const rpcUrl = process.env.RPC_URL;
if (!rpcUrl) {
  throw new Error("RPC_URL is not set");
}

// CLAUDE.md documents RPC_URL as "WebSocket-capable" for order-indexer —
// use a real WS subscription (push-based, lower latency) when given one,
// falling back to HTTP (viem's built-in polling) otherwise so a plain
// https:// URL still works.
const transport = rpcUrl.startsWith("ws://") || rpcUrl.startsWith("wss://") ? webSocket(rpcUrl) : http(rpcUrl);

export const publicClient = createPublicClient({
  chain: sepolia,
  transport,
});
