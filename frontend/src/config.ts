import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { getAddress, isAddress, type Address } from "viem";

function readAddress(name: string, value: string | undefined): Address {
  if (!value || !isAddress(value)) {
    throw new Error(`${name} is not set to a valid Ethereum address`);
  }
  return getAddress(value);
}

const rpcUrl = import.meta.env.VITE_RPC_URL;
if (!rpcUrl) {
  throw new Error("VITE_RPC_URL is not set");
}

const contractAddress = readAddress("VITE_CONTRACT_ADDRESS", import.meta.env.VITE_CONTRACT_ADDRESS);
const configuredWethAddress = readAddress("VITE_WETH_ADDRESS", import.meta.env.VITE_WETH_ADDRESS);
const quoteTokenAddress = readAddress("VITE_QUOTE_TOKEN_ADDRESS", import.meta.env.VITE_QUOTE_TOKEN_ADDRESS);

const envIndexerUrl = import.meta.env.VITE_INDEXER_URL;
if (!envIndexerUrl) {
  throw new Error("VITE_INDEXER_URL is not set");
}

// order-indexer's base URL, used to read order history.
export const indexerUrl: string = envIndexerUrl;

// OrderKeeper's deployed address on Sepolia, read from env rather than
// deployments/sepolia.json (unlike order-indexer/keeper-bot): the frontend
// is a browser bundle, not a Node process with filesystem access.
export const orderKeeperAddress = contractAddress;

// WETH's Sepolia address (deployments/sepolia.json's "weth"): the asset
// every order's price condition gates on, and the non-quoteToken side of
// every swap.
//
// A previous revision carried a multi-asset selector here (BTC/LINK/USDC).
// It was removed deliberately: those assets only ever chose which Chainlink
// feed the condition read — none of them could actually be traded, and
// verifying the Uniswap V2 pools later showed LINK has no Sepolia pool at
// all. Supporting one real pair in both directions is the honest version of
// the same product. See ROADMAP.md's Milestone 12.
export const wethAddress = configuredWethAddress;

// The ERC20 side of the pair (deployments/sepolia.json's "quoteToken"):
// what Sell orders receive and what Buy orders deposit. Decimals are
// fixed to match DemoUSDC's 6 — amounts are no longer always 18-decimal
// now that Buy orders deposit this token instead of ETH.
//
// MUST match the live OrderKeeper's own quoteToken() exactly, not just be
// "a" DemoUSDC deployment — DemoUSDC has no canonical fixed address (each
// deploy script run deploys a fresh instance), so a stale environment
// value can still point to an earlier deployment. That happened once: the
// frontend pointed at a leftover mUSDC while the
// live contract's real quoteToken() had moved to a different address.
// Both happened to share the "mUSDC" symbol and 6 decimals, so nothing
// about the mismatch was visually obvious — Buy's approve() succeeded
// against the wrong token, then createOrder()'s real safeTransferFrom
// reverted for insufficient allowance, silently (no OrderCreated event,
// so order-indexer showed nothing). Cross-check against
// `cast call <OrderKeeperAddress> "quoteToken()(address)" --rpc-url sepolia`
// after every redeploy, not just against deployments/sepolia.json.
export const quoteToken = {
  label: "mUSDC",
  address: quoteTokenAddress,
  decimals: 6,
} as const;

// Sepolia only — this project's only target network (see CLAUDE.md).
export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(rpcUrl),
  },
});
