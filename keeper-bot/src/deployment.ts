import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import type { Address } from "viem";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Sepolia is this project's only target network today (see CLAUDE.md) —
// hardcoded rather than added as a second env var alongside PRIVATE_KEY/
// RPC_URL until a real second network is actually in scope.
const DEPLOYMENT_FILE = path.resolve(__dirname, "../../deployments/sepolia.json");

interface DeploymentRecord {
  chainId: number;
  OrderKeeper: Address;
  quoteToken: Address;
  weth: Address;
  uniswapRouter: Address;
  priceFeed: Address;
  deployedAt: number;
}

/// Reads the OrderKeeper contract address from deployments/sepolia.json —
/// deliberately not an env var (see that directory's README): the
/// deployed address is a fact about the chain, not per-service config.
export function loadDeployment(): DeploymentRecord {
  let raw: string;
  try {
    raw = readFileSync(DEPLOYMENT_FILE, "utf-8");
  } catch {
    throw new Error(
      `Could not read ${DEPLOYMENT_FILE} — has contracts/script/DeployOrderKeeper.s.sol been run yet?`,
    );
  }

  try {
    return JSON.parse(raw) as DeploymentRecord;
  } catch {
    throw new Error(`Could not parse ${DEPLOYMENT_FILE} — is it valid JSON?`);
  }
}
