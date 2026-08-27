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

// Sepolia only — this project's only target network (see CLAUDE.md).
export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(rpcUrl),
  },
});
