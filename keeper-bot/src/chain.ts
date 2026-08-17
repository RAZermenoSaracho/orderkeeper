import { createPublicClient, createWalletClient, http, webSocket, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";

const rpcUrl = process.env.RPC_URL;
if (!rpcUrl) {
  throw new Error("RPC_URL is not set");
}

const privateKey = process.env.PRIVATE_KEY;
if (!privateKey) {
  throw new Error("PRIVATE_KEY is not set");
}

// Same operator key used for both reads and writes — separate from the
// contracts/ deployer key (per CLAUDE.md's Environment Variables: never
// share keys between services).
export const operatorAccount = privateKeyToAccount(privateKey as Hex);

// WS if given one (push-based), HTTP/polling fallback otherwise — same
// transport-selection logic as order-indexer/src/chain.ts.
const transport = rpcUrl.startsWith("ws://") || rpcUrl.startsWith("wss://") ? webSocket(rpcUrl) : http(rpcUrl);

/// Read-only client: eth_call for checkPriceCondition().
export const publicClient = createPublicClient({
  chain: sepolia,
  transport,
});

/// Signing client: sends executeOrder() transactions as operatorAccount.
export const walletClient = createWalletClient({
  account: operatorAccount,
  chain: sepolia,
  transport,
});
