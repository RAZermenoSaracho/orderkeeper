import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import type { Address } from "viem";

const rpcUrl = import.meta.env.VITE_RPC_URL;
if (!rpcUrl) {
  throw new Error("VITE_RPC_URL is not set");
}

const contractAddress = import.meta.env.VITE_CONTRACT_ADDRESS;
if (!contractAddress) {
  throw new Error("VITE_CONTRACT_ADDRESS is not set");
}

const envIndexerUrl = import.meta.env.VITE_INDEXER_URL;
if (!envIndexerUrl) {
  throw new Error("VITE_INDEXER_URL is not set");
}

// order-indexer's base URL, used to read order history.
export const indexerUrl: string = envIndexerUrl;

// OrderKeeper's deployed address on Sepolia, read from env rather than
// deployments/sepolia.json (unlike order-indexer/keeper-bot): the frontend
// is a browser bundle, not a Node process with filesystem access.
export const orderKeeperAddress = contractAddress as Address;

export interface SupportedAsset {
  label: string;
  address: Address;
}

// Assets with a Chainlink feed registered via addPriceFeed() (see
// RUNBOOK.md's "Register additional price feeds" workflow) — hardcoded
// rather than a free-text input on the order form, same reasoning as the
// original WETH-only version: order.asset only selects which Chainlink
// feed the price condition checks against (see CLAUDE.md's Design
// Decisions), it's never a token the contract actually calls, so these
// addresses are oracle lookup keys, not swap-path tokens. WETH stays
// first/default, matching prior behavior.
export const SUPPORTED_ASSETS: readonly SupportedAsset[] = [
  { label: "WETH", address: "0x1287B650e882514447b96a49a0f8DC1040B26d2A" },
  // No canonical Sepolia BTC token exists (BTC isn't a native EVM asset)
  // — this is a deterministic placeholder (keccak256("BTC")'s last 20
  // bytes, same convention as Foundry's makeAddr()), not a real contract.
  { label: "BTC", address: "0x505e65d08c67660dc618072422e9c78053c261e9" },
  // Real Sepolia LINK token (Chainlink's own testnet faucet token).
  { label: "LINK", address: "0x779877A7B0D9E8603169DdbD7836e478b4624789" },
  // Real Sepolia USDC token (Circle's official testnet deployment).
  { label: "USDC", address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" },
  // DAI is intentionally NOT offered here even though its feed is
  // registered on-chain (addPriceFeed() already called, not reverted) —
  // low Sepolia testnet activity leaves it intermittently stale beyond
  // OrderKeeper's PRICE_STALENESS_THRESHOLD, making it unreliable for a
  // live demo. See ISSUES.md's "Sepolia DAI feed is registered but
  // intermittently stale" entry.
] as const;

// Sepolia only — this project's only target network (see CLAUDE.md).
export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(rpcUrl),
  },
});
