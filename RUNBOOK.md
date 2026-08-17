# Manual Verification Runbook

A home for manual, human-run verification workflows for this repo —
checks that don't fit into `forge test`/CI because they need live
external state (a real chain, a real RPC, real gas) or a human confirming
something directly. Add a new `## Workflow: ...` section here whenever a
new one is needed, rather than starting a new file per workflow.

**These are checklists for you to run yourself.** Nothing in this file
gets executed automatically or on your behalf.

## Contents

- [End-to-end oracle loop verification](#workflow-end-to-end-oracle-loop-verification)

Add a new entry here alongside each new `## Workflow: ...` section.

---

## Workflow: End-to-end oracle loop verification

Proves the full oracle-to-execution loop live on Sepolia — not just in
tests: `createOrder()` → `order-indexer` → `keeper-bot` →
`checkPriceCondition()` → `executeOrder()`. Mirrors how Module 13's
`getAssetPrice()` was proven live with `cast call` rather than only
unit-tested; here the loop is longer, so more steps, same idea.

Already run successfully once — see README.md's
[On-Chain Activity](README.md#on-chain-activity) section for that
specific run's tx hashes and figures. Use this workflow to reproduce it,
or to verify again after future changes.

### Prerequisites

- [ ] `contracts/.env`, `order-indexer/.env`, and `keeper-bot/.env` all
      filled in (copy from each directory's `.env.example` if starting
      fresh).
- [ ] `keeper-bot/.env`'s `PRIVATE_KEY` is a **separate wallet** from
      `contracts/.env`'s deployer key — never the same one (CLAUDE.md
      Environment Variables). It needs enough Sepolia ETH to pay gas for
      `executeOrder()` — 0.01 ETH is comfortably enough for many
      executions at current gas prices.
- [ ] Whichever wallet you use to call `createOrder()` below has enough
      Sepolia ETH to cover the order amount plus gas — it can be any
      funded wallet, including the deployer key, since `createOrder()`
      doesn't care who calls it.
- [ ] Local PostgreSQL running, `orderkeeper_dev` database exists, and
      migrations are applied (`cd order-indexer && npx prisma migrate deploy`
      if you haven't already).
- [ ] `foundry` and `node` installed.

### Step 0 — Deploy (skip if verifying against the existing deployment)

`deployments/sepolia.json` already has a live deployment. Skip to Step 1
unless you specifically need a fresh one.

To deploy fresh:

```shell
cd contracts
forge script script/DeployOrderKeeper.s.sol --rpc-url sepolia --broadcast --slow
```

`--slow` waits for each transaction to confirm before sending the next —
required for `addLiquidityETH`'s deadline to still be valid by the time
that transaction actually broadcasts (see `DEADLINE_BUFFER` in the script;
this was a real bug the first time this script ran).

- [ ] Confirm `deployments/sepolia.json` was written with all six fields
      (`OrderKeeper`, `quoteToken`, `weth`, `uniswapRouter`, `priceFeed`,
      `chainId`).

### Step 1 — Start `order-indexer`

```shell
cd order-indexer
npm run dev
```

- [ ] Log shows `Indexing OrderKeeper at 0x...` and `Server listening at
      http://...`.
- [ ] `curl http://localhost:3001/health` returns `{"status":"ok"}`.

### Step 2 — Start `keeper-bot`

In a second terminal:

```shell
cd keeper-bot
npm run dev
```

- [ ] Log shows `[keeper-bot] Operator: 0x...`, `Watching OrderKeeper at
      0x...`, and `Polling http://localhost:3001 every 15s`.

### Step 3 — Create a real test order

In a third terminal. This sends a real transaction and costs a small
amount of Sepolia ETH.

```shell
cd contracts

CONTRACT=0xe634c848941Fe06860fbF26B7F9F1E5496ed6F2b
WETH=0x1287B650e882514447b96a49a0f8DC1040B26d2A

# 1. Read the live price first — never guess it.
cast call $CONTRACT "getAssetPrice(address)(uint256)" $WETH --rpc-url sepolia

# 2. Create an order with a target comfortably BELOW the live price you
#    just read (GreaterOrEqual, so it's already true and stays true
#    through any realistic price movement before keeper-bot picks it up).
#    Replace TARGET_PRICE below — e.g. if live price is ~1900e18, use
#    something like 1000000000000000000000 ($1,000).
cast send $CONTRACT \
  "createOrder(address,uint8,uint256,uint256,uint256)" \
  $WETH \
  0 \
  TARGET_PRICE \
  100 \
  $(($(date +%s) + 3600)) \
  --value 0.001ether \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

- [ ] Transaction receipt shows `status: 1 (success)`.

### Step 4 — Watch `order-indexer` pick it up

```shell
curl -s "http://localhost:3001/orders?status=pending"
```

- [ ] Your new order appears, with `status: "Pending"` and the `asset`/
      `targetPrice`/`amount` you just set. If it doesn't appear within a
      few seconds, check `order-indexer`'s terminal for errors (see
      Troubleshooting).

### Step 5 — Watch `keeper-bot` detect and execute it

Watch `keeper-bot`'s terminal. Within one 15-second poll cycle:

- [ ] `[keeper-bot] executeOrder(N) submitted: 0x...` appears.

If instead you see `executeOrder(N) reverted (...) — expected race,
retrying next cycle`, that's not a failure — it means `order-indexer`
hadn't indexed the order yet when that particular poll ran. It should
succeed on the next cycle.

### Step 6 — Confirm final state

```shell
curl -s "http://localhost:3001/orders?status=pending"    # should no longer include your order
curl -s "http://localhost:3001/orders?status=executed"   # should now include it
```

- [ ] The executed record includes `executionPrice`, `keeperFee`, and
      `amountOut`, all pulled from the real `OrderExecuted` event.
- [ ] Both the `createOrder()` and `executeOrder()` tx hashes resolve on
      [Sepolia Etherscan](https://sepolia.etherscan.io) — the
      `executeOrder()` transaction shows an internal ETH transfer (the
      keeper fee, to `keeper-bot`'s operator address) and a DemoUSDC
      transfer (the swap output, to the order owner's address).

### Troubleshooting

- **`executeOrder()` never gets submitted, no revert logged either** —
  check `keeper-bot`'s operator wallet balance; it needs Sepolia ETH for
  gas, separate from whatever funded the `createOrder()` call.
- **Order never shows up as pending** — check `order-indexer`'s terminal
  for `eth_getLogs` errors. If your RPC provider's free tier caps the
  block range per call (Alchemy's is 10 blocks), `GETLOGS_BLOCK_RANGE` in
  `order-indexer/.env` may need lowering.
- **`executeOrder()` keeps reverting with `ConditionNotMet`** — double
  check `TARGET_PRICE` in Step 3 was actually set below the live price you
  read (for `GreaterOrEqual`) — a copy-paste of the live price itself,
  rather than something clearly below it, can flip false on the very next
  block if the price ticks down even slightly.
- **`prisma` complains about authentication** — `DATABASE_URL` in
  `order-indexer/.env` needs an explicit username under Homebrew
  Postgres's peer/trust auth — see the comment in that file's
  `.env.example`.
