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

// OrderKeeper's deployed address on Sepolia, read from env rather than
// deployments/sepolia.json (unlike order-indexer/keeper-bot): the frontend
// is a browser bundle, not a Node process with filesystem access.
export const orderKeeperAddress = contractAddress as Address;

// WETH's Sepolia address, hardcoded from deployments/sepolia.json's "weth"
// field rather than a free-text input on the order form — order.asset only
// selects which Chainlink feed the price condition checks against (see
// CLAUDE.md's Design Decisions), and WETH/USD is the only feed this MVP's
// order form needs to offer.
export const defaultAssetAddress: Address = "0x1287B650e882514447b96a49a0f8DC1040B26d2A";

// Sepolia only — this project's only target network (see CLAUDE.md).
export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(rpcUrl),
  },
});
