# Manual Verification Runbook

A home for manual, human-run verification workflows for this repo —
checks that don't fit into `forge test`/CI because they need live
external state (a real chain, a real RPC, real gas) or a human confirming
something directly. Add a new `## Workflow: ...` section here whenever a
new one is needed, rather than starting a new file per workflow.

**These are checklists for you to run yourself.** Nothing in this file
gets executed automatically or on your behalf.

## Contents

- [Run full test suite](#workflow-run-full-test-suite)
- [Deploy contracts](#workflow-deploy-contracts)
- [Verify contract on Etherscan](#workflow-verify-contract-on-etherscan)
- [End-to-end oracle loop verification](#workflow-end-to-end-oracle-loop-verification)
- [Multiple competing keeper-bots](#workflow-multiple-competing-keeper-bots)
- [Register additional price feeds](#workflow-register-additional-price-feeds)

Add a new entry here alongside each new `## Workflow: ...` section.

---

## Workflow: Run full test suite

Runs everything `forge test`/`forge coverage` can check locally. Unit and
invariant tests need no network access. Fork tests need `RPC_URL`
configured (`contracts/.env`, resolved via the `sepolia` alias in
`foundry.toml`) — they read live Sepolia state (the real Chainlink feed,
the real Uniswap pool) but send no real transactions, so they cost no gas.

```shell
cd contracts

# Unit tests (OrderKeeperTest + DemoUSDCTest)
forge test --match-contract "OrderKeeperTest|DemoUSDCTest"

# Invariant test (solvency: contract balance == sum of active order amounts)
forge test --match-contract OrderKeeperInvariantTest

# Fork tests (reads live Sepolia state — no gas spent, nothing broadcast)
forge test --fork-url sepolia --match-contract OrderKeeperForkTest

# Fuzz tests specifically — a subset of the unit suite above, isolated
# here for a quick fuzz-only pass
forge test --match-test testFuzz -vv

# Coverage report (unit + invariant only — forge coverage doesn't take --fork-url)
forge coverage
```

**Expected results** (as of 2026-08-17 — if your numbers differ, that's a
signal to investigate what changed, not necessarily a problem):

- [ ] Unit: `61 passed; 0 failed` (`OrderKeeperTest`: 51, `DemoUSDCTest`: 10).
- [ ] Invariant: `1 passed; 0 failed` (256 runs, 128,000 calls, 0 reverts
      against the invariant itself).
- [ ] Fork: `4 passed; 0 failed`.
- [ ] Fuzz: `3 passed; 0 failed` (256 runs each — already counted within
      the unit total above; this run just isolates them).
- [ ] Coverage: `src/OrderKeeper.sol` and `src/DemoUSDC.sol` both 100%
      lines/statements/branches/functions.
- [ ] Plain `forge test` with no flags (fork suite self-skips without
      `--fork-url`): `62 passed; 0 failed; 1 skipped`.

---

## Workflow: Deploy contracts

Deploys `OrderKeeper`, a fresh `DemoUSDC` quote token, registers the real
Chainlink ETH/USD feed, and seeds initial WETH/DemoUSDC Uniswap liquidity.
See `contracts/script/DeployOrderKeeper.s.sol` for full details.

`deployments/sepolia.json` already has a live deployment — you only need
this workflow for a genuinely fresh deploy (a new environment, or after a
contract change that needs redeploying).

### Prerequisites

- [ ] `contracts/.env` filled in: `RPC_URL`, `PRIVATE_KEY` (deployer key),
      `CHAINLINK_ETH_USD_FEED`, `UNISWAP_ROUTER_ADDRESS`.
      `INITIAL_LIQUIDITY_ETH` is optional (defaults to 1 ETH).
- [ ] Deployer wallet funded with enough Sepolia ETH to cover
      `INITIAL_LIQUIDITY_ETH` plus gas for six transactions.

### Dry run (no transactions sent, no gas spent)

Always do this first — simulates the full script against a local fork,
without broadcasting anything to the real chain:

```shell
cd contracts
forge script script/DeployOrderKeeper.s.sol --rpc-url sepolia
```

- [ ] `SIMULATION COMPLETE` with no revert; estimated gas/ETH cost looks
      sane.

**⚠️ This overwrites `deployments/sepolia.json` with fake, never-deployed
addresses — even without `--broadcast`.** Confirmed by actually running
this: `vm.writeJson` is a cheatcode, not a transaction, so it executes
during simulation regardless of `--broadcast`. Only the six on-chain
transactions themselves are gated by `--broadcast`; the JSON write isn't.
If you're dry-running against an existing real deployment, restore the
file immediately after:

```shell
git status deployments/sepolia.json   # confirm it changed
git restore deployments/sepolia.json  # restore the real record
```

### Real deploy (sends real transactions, costs real Sepolia ETH)

```shell
cd contracts
forge script script/DeployOrderKeeper.s.sol --rpc-url sepolia --broadcast --slow
```

`--slow` waits for each transaction to confirm before sending the next —
required for `addLiquidityETH`'s deadline to still be valid by the time
that transaction actually broadcasts (see `DEADLINE_BUFFER` in the script;
this was a real bug the first time this script ran).

- [ ] All six transactions confirm (`DemoUSDC` deploy, `OrderKeeper`
      deploy, `addPriceFeed`, `DemoUSDC.mint`, `DemoUSDC.approve`,
      `addLiquidityETH`).
- [ ] `deployments/sepolia.json` was written with all six fields
      (`OrderKeeper`, `quoteToken`, `weth`, `uniswapRouter`, `priceFeed`,
      `chainId`) — this time for real, since transactions actually landed.
- [ ] Transaction details also recorded in Foundry's own
      `contracts/broadcast/DeployOrderKeeper.s.sol/11155111/run-latest.json`.

---

## Workflow: Verify contract on Etherscan

Verifies `OrderKeeper`'s source code on Sepolia Etherscan, so anyone can
read it and interact with it directly from the block explorer without
trusting a locally-compiled ABI.

### Prerequisites

- [ ] `ETHERSCAN_API_KEY` — not yet in `contracts/.env.example`; get one
      free at https://etherscan.io/apis and export it before running this.
- [ ] The contract is already deployed (`deployments/sepolia.json` has an
      `OrderKeeper` address).
- [ ] `jq` installed (or read the addresses out of
      `deployments/sepolia.json` by hand instead of the `jq` commands below).

### Verify

```shell
cd contracts

CONTRACT=$(jq -r .OrderKeeper ../deployments/sepolia.json)
QUOTE_TOKEN=$(jq -r .quoteToken ../deployments/sepolia.json)
UNISWAP_ROUTER=$(jq -r .uniswapRouter ../deployments/sepolia.json)
OWNER=$(cast call $CONTRACT "owner()(address)" --rpc-url sepolia)

forge verify-contract \
  $CONTRACT \
  src/OrderKeeper.sol:OrderKeeper \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $OWNER $QUOTE_TOKEN $UNISWAP_ROUTER) \
  --watch
```

- [ ] Command reports contract successfully verified.
- [ ] The contract's page on
      [Sepolia Etherscan](https://sepolia.etherscan.io) shows a green
      checkmark next to "Contract" and exposes "Read Contract"/"Write
      Contract" tabs.

`DemoUSDC` can be verified the same way — substitute
`src/DemoUSDC.sol:DemoUSDC` and `$QUOTE_TOKEN` for the address, and drop
`--constructor-args` entirely (it takes no constructor arguments).

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

Need a deployment first? See **Workflow: Deploy contracts** above —
`deployments/sepolia.json` already has a live one, so skip that unless you
need a fresh deploy.

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
- **`executeOrder()` reverts with `UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT`
  even though the condition is clearly met** — the WETH/DemoUSDC pool's own
  reserves ratio can drift from the live oracle price over time (no
  arbitrage bots trade this testnet pool). If the gap exceeds your order's
  `maxSlippageBps`, the swap correctly refuses to execute at a bad price —
  that's the slippage protection working as designed, not a bug. Either
  accept a wider `maxSlippageBps` for testing, or add more liquidity to
  rebalance the pool.
- **`prisma` complains about authentication** — `DATABASE_URL` in
  `order-indexer/.env` needs an explicit username under Homebrew
  Postgres's peer/trust auth — see the comment in that file's
  `.env.example`.

## Workflow: Multiple competing keeper-bots

Proves the "permissionless execution" premise for real — that anyone can
run a `keeper-bot` and compete for the keeper fee — by running two real
instances against the same live deployment and confirming the existing
race-condition handling (`keeper.ts`'s `EXPECTED_RACE_ERRORS`) holds up
under actual concurrent competition, not just one bot's own retry logic.
See ROADMAP.md's Milestone 10.

### Prerequisites

- [ ] Everything from **Workflow: End-to-end oracle loop verification**
      above already working (`order-indexer` + one `keeper-bot` instance).
- [ ] A **second** operator wallet, separate from the first `keeper-bot`'s
      key and from the `contracts/` deployer key — three distinct keys in
      total, never shared (CLAUDE.md Environment Variables). Funded with
      ~0.01 Sepolia ETH, same as the first.
- [ ] A second env file for it: `keeper-bot/.env.local` (already covered
      by `.gitignore`'s `.env.local` pattern — don't invent a new
      filename without checking it's actually ignored first). Same
      contents as `keeper-bot/.env`, except `PRIVATE_KEY` is the second
      wallet's key.

### Step 1 — Start both keeper-bot instances

In two separate terminals:

```shell
cd keeper-bot
npm run dev                                        # instance 1, uses .env
```

```shell
cd keeper-bot
tsx watch --env-file=.env.local src/index.ts        # instance 2, uses .env.local
```

- [ ] Both logs show a different `[keeper-bot] Operator: 0x...` address.
- [ ] Both show `Watching OrderKeeper at` the same contract address.

### Step 2 — Create a real test order

Same as Step 3 in the end-to-end workflow above — a fresh order with a
trivially-true condition so both instances see it as executable on their
very next poll.

### Step 3 — Watch both terminals for the race

Within one or two 15-second poll cycles:

- [ ] **One** instance logs `executeOrder(N) submitted: 0x...`.
- [ ] The **other** instance logs `executeOrder(N) reverted (OrderNotPending)
      — expected race, retrying next cycle` — this is the actual thing
      this workflow exists to prove, not a failure.

If both instances happen to submit in the same block window before either
transaction lands, you may instead see the loser's revert come from a
mined transaction rather than the pre-broadcast simulation (still caught
by the same `EXPECTED_RACE_ERRORS` handling) — either shape confirms the
behavior.

### Step 4 — Confirm final state

```shell
curl -s "http://localhost:3001/orders?status=executed"
```

- [ ] The order shows exactly one execution — `executedAtTx` resolves on
      Sepolia Etherscan to whichever instance actually won, and the
      keeper fee went to that instance's operator address, not the
      loser's.

### Troubleshooting

- **Neither instance ever logs a race** — the two poll cycles probably
  landed too far apart (e.g. started several seconds apart) for both to
  see the order as pending on the same cycle. Restart both closer
  together, or lengthen the order's window by using a condition that
  stays true for longer before either bot's first poll.
- **Both instances submit and both succeed** — shouldn't happen
  (`executeOrder()` flips the order to `Executed` on the first success,
  which the second call's simulation should see) — if it does, that's a
  real bug in the contract's state transition, not an expected race; stop
  and investigate rather than re-running.

## Workflow: Register additional price feeds

Registers Chainlink feeds for the four additional assets the frontend's
multi-asset selector offers alongside WETH — `addPriceFeed()` is
`onlyOwner`, so these are real transactions from the deployer wallet, not
something to run automatically. See ROADMAP.md's Milestone 12.

Every address below was verified directly against Sepolia before being
used here — `eth_getCode` to confirm it's a real contract, then `symbol()`
(for the three real tokens) or `description()` (for the feeds) to confirm
it's the right one. Don't add a new asset to `frontend/src/config.ts`'s
`SUPPORTED_ASSETS` without doing the same — search results and doc pages
have repeatedly returned mainnet addresses mislabeled as Sepolia earlier
in this project's history; only an on-chain check is trustworthy.

| Asset | `asset` address (lookup key) | Feed address |
|---|---|---|
| BTC | `0x505e65d08c67660dc618072422e9c78053c261e9` (synthetic — no canonical Sepolia BTC token exists; this is `keccak256("BTC")`'s last 20 bytes, same convention as Foundry's `makeAddr()`) | `0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43` |
| LINK | `0x779877A7B0D9E8603169DdbD7836e478b4624789` (real Sepolia LINK, Chainlink's own testnet faucet token) | `0xc59E3633BAAC79493d908e63626716e204A45EdF` |
| USDC | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` (real Sepolia USDC, Circle's official testnet deployment) | `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E` |
| DAI | `0xff34b3d4aee8ddcd6f9afffb6fe49bd371b8a357` (a Sepolia token with `symbol() == "DAI"` — no single canonical issuer for Sepolia DAI, treat as "a" DAI-like token, not "the" one) | `0x14866185B1962B63C3Ea9E03Bc1da838bab34C19` |

Recall `order.asset` is purely an oracle lookup key — the contract never
calls it, never checks it's a real token (see CLAUDE.md's Design
Decisions on `order.asset` being oracle-only). The `asset` addresses
above only need to be stable and unique, not "real" in any deeper sense;
BTC's is synthetic for exactly that reason.

### Prerequisites

- [ ] `contracts/.env` filled in, with `PRIVATE_KEY` set to the **deployer
      key** — `addPriceFeed()` is `onlyOwner`, and the deployer is the
      contract's owner.
- [ ] Deployer wallet has enough Sepolia ETH for four small transactions'
      gas.

### Register each feed

```shell
cd contracts
CONTRACT=0x2d065b6a75A207e73Cc9f76953A5886B250336FD

# BTC
cast send $CONTRACT "addPriceFeed(address,address)" \
  0x505e65d08c67660dc618072422e9c78053c261e9 \
  0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 \
  --rpc-url sepolia --private-key $PRIVATE_KEY

# LINK
cast send $CONTRACT "addPriceFeed(address,address)" \
  0x779877A7B0D9E8603169DdbD7836e478b4624789 \
  0xc59E3633BAAC79493d908e63626716e204A45EdF \
  --rpc-url sepolia --private-key $PRIVATE_KEY

# USDC
cast send $CONTRACT "addPriceFeed(address,address)" \
  0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 \
  0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E \
  --rpc-url sepolia --private-key $PRIVATE_KEY

# DAI
cast send $CONTRACT "addPriceFeed(address,address)" \
  0xff34b3d4aee8ddcd6f9afffb6fe49bd371b8a357 \
  0x14866185B1962B63C3Ea9E03Bc1da838bab34C19 \
  --rpc-url sepolia --private-key $PRIVATE_KEY
```

- [ ] All four transactions show `status: 1 (success)`.

### Confirm each feed is live

```shell
cast call $CONTRACT "getAssetPrice(address)(uint256)" \
  0x505e65d08c67660dc618072422e9c78053c261e9 --rpc-url sepolia   # BTC
cast call $CONTRACT "getAssetPrice(address)(uint256)" \
  0x779877A7B0D9E8603169DdbD7836e478b4624789 --rpc-url sepolia   # LINK
cast call $CONTRACT "getAssetPrice(address)(uint256)" \
  0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 --rpc-url sepolia   # USDC
cast call $CONTRACT "getAssetPrice(address)(uint256)" \
  0xff34b3d4aee8ddcd6f9afffb6fe49bd371b8a357 --rpc-url sepolia   # DAI
```

- [ ] Each returns a plausible non-zero, 18-decimal price rather than
      reverting with `UnsupportedAsset`.
- [ ] In the frontend (`npm run dev` in `frontend/`), the Create Order
      form's Asset dropdown shows a live price (not "Price unavailable")
      for each of BTC / LINK / USDC / DAI once selected.

### Troubleshooting

- **Reverts with `UnsupportedAsset`** — the transaction for that asset
  either didn't land yet or used the wrong `asset` address; double-check
  against the table above, not from memory.
- **`addPriceFeed` reverts with an ownership error** — `PRIVATE_KEY` in
  `contracts/.env` isn't the deployer key. Check against
  `deployments/sepolia.json`'s deployment record, or `cast call $CONTRACT
  "owner()(address)" --rpc-url sepolia`.
