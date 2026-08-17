# Deployments

Deployed contract addresses per chain/environment, per `CLAUDE.md`'s
Planned Structure. One JSON file per target, written automatically by
`contracts/script/DeployOrderKeeper.s.sol` on every run — e.g. `sepolia.json`:

```json
{
  "chainId": 11155111,
  "OrderKeeper": "0x...",
  "quoteToken": "0x...",
  "weth": "0x...",
  "uniswapRouter": "0x...",
  "priceFeed": "0x...",
  "deployedAt": 1234567890
}
```

`quoteToken` is `DemoUSDC` — a testnet-only mintable stand-in for a USD
stablecoin, deployed by the same script (see `contracts/src/DemoUSDC.sol`
for why: no real WETH/stablecoin Uniswap V2 pair exists yet on Sepolia's
router). `deployedAt` is a Unix timestamp. Transaction-level detail
(hashes, gas used) isn't duplicated here — it already lives in Foundry's
own `contracts/broadcast/` artifacts; this file is a quick-reference
summary of addresses.

Populated automatically the first time `DeployOrderKeeper.s.sol` is run
with `--broadcast`. Not yet run.
