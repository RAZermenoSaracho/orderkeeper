---
name: deploy
description: Safely deploy OrderKeeper and its DemoUSDC liquidity setup to Sepolia.
---

# Deploy OrderKeeper

This workflow is manual because it broadcasts transactions and spends Sepolia
ETH. Never run it without Ricardo's explicit authorization for that session.

1. Read the root `CLAUDE.md`, `RUNBOOK.md`'s deployment workflow, and
   `deploy-config.md`.
2. Confirm `contracts/.env` contains `RPC_URL`, `PRIVATE_KEY`,
   `CHAINLINK_ETH_USD_FEED`, and `UNISWAP_ROUTER_ADDRESS`; never print their
   values.
3. Run the safe dry run first:
   `forge script script/DeployOrderKeeper.s.sol --rpc-url sepolia`.
   Dry runs do not alter `deployments/sepolia.json`.
4. Stop and obtain explicit authorization before adding `--broadcast --slow`.
5. After a successful broadcast, verify that `deployments/sepolia.json`
   contains the new addresses and `deploymentBlock`.
6. Cross-check `OrderKeeper.quoteToken()` and `OrderKeeper.weth()` on-chain,
   then copy all three deployment addresses into the frontend environment.
7. Follow `RUNBOOK.md` for Etherscan verification and live end-to-end checks.

Sepolia is the only supported deployment target for this MVP.
