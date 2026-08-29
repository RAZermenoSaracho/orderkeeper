# Deployments

Deployed contract addresses per chain/environment, per `CLAUDE.md`'s
Planned Structure. One JSON file per target, written automatically by
`contracts/script/DeployOrderKeeper.s.sol` after a broadcast or resumed
broadcast — never during a dry run. For example, `sepolia.json`:

```json
{
  "chainId": 11155111,
  "deploymentBlock": 12345678,
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
router). `deploymentBlock` is where a fresh indexer begins its historical
backfill, and `deployedAt` is a Unix timestamp. Transaction-level detail
(hashes, gas used) isn't duplicated here — it already lives in Foundry's
own `contracts/broadcast/` artifacts; this file is a quick-reference
summary of addresses.

The current Sepolia record is populated from the successful 2026-08-29
broadcast. Future successful broadcasts replace it with the new deployment;
dry runs leave it unchanged.
