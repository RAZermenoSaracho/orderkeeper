# Sepolia Deploy Config

- Chain ID: `11155111`
- Deployment script: `contracts/script/DeployOrderKeeper.s.sol`
- Canonical record: `deployments/sepolia.json`
- RPC, deployer key, Chainlink ETH/USD feed, and Uniswap V2 router are read
  from `contracts/.env` as documented by `contracts/.env.example`.
- The script deploys a fresh DemoUSDC and seeds its WETH pair.
- Only broadcast/resume execution updates the canonical deployment record.

No other chain or environment is supported by the current MVP.
