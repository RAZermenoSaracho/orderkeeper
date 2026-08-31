# Manual Verification Runbook

A home for manual, human-run verification workflows for this repo —
checks that don't fit into `forge test`/CI because they need live
external state (a real chain, a real RPC, real gas) or a human confirming
something directly. Add a new `## Workflow: ...` section here whenever a
new one is needed, rather than starting a new file per workflow.

**These are checklists for you to run yourself.** Nothing in this file
gets executed automatically or on your behalf.

## Table of Contents

- [Run full test suite](#workflow-run-full-test-suite)
- [Deploy contracts](#workflow-deploy-contracts)
- [Verify contract on Etherscan](#workflow-verify-contract-on-etherscan)
- [Fresh PostgreSQL setup or intentional legacy reset](#workflow-fresh-postgresql-setup-or-intentional-legacy-reset)
- [Build and prepare MacBook services for PM2](#workflow-build-and-prepare-macbook-services-for-pm2)
- [Continuous deployment to the MacBook](#workflow-continuous-deployment-to-the-macbook)
- [End-to-end oracle loop verification](#workflow-end-to-end-oracle-loop-verification)
- [Multiple competing keeper-bots](#workflow-multiple-competing-keeper-bots)

Add a new entry here alongside each new `## Workflow: ...` section.

---

## Workflow: Run full test suite

Runs everything each service's own test command can check locally.
`contracts/`'s unit and invariant tests need no network access; its fork
tests need `RPC_URL` configured (`contracts/.env`, resolved via the
`sepolia` alias in `foundry.toml`) — they read live Sepolia state (the
real Chainlink feed, the real Uniswap pool) but send no real
transactions, so they cost no gas. `order-indexer/`, `keeper-bot/`, and
`frontend/` each run via Vitest (`npm test`) and need no network access
either — see each directory's `CLAUDE.md` for their testing conventions
(mocking patterns, file organization).

### `contracts/`

```shell
cd contracts

# Unit tests (OrderKeeperTest + DemoUSDCTest)
forge test --match-contract "OrderKeeperTest|DemoUSDCTest"

# Invariant tests (three: ETH solvency, quoteToken solvency, no stranded
# router allowance — see OrderKeeper.invariant.t.sol)
forge test --match-contract OrderKeeperInvariantTest

# Fork tests (reads live Sepolia state — no gas spent, nothing broadcast)
forge test --fork-url sepolia --match-contract OrderKeeperForkTest

# Fuzz tests specifically — a subset of the unit suite above, isolated
# here for a quick fuzz-only pass
forge test --match-test testFuzz -vv

# Coverage report (unit + invariant only — forge coverage doesn't take --fork-url)
forge coverage
```

**Expected results** (as of 2026-08-30 — if your numbers differ, that's a
signal to investigate what changed, not necessarily a problem):

- [ ] Unit: `73 passed; 0 failed` (`OrderKeeperTest`: 62, `DemoUSDCTest`:
      10, `DeployOrderKeeperTest`: 1 — the `--match-contract` pattern
      above matches all three; `DeployOrderKeeperTest` tests deploy-script
      behavior, not `OrderKeeper` itself, but is unit-scoped the same way).
- [ ] Invariant: `3 passed; 0 failed` — `invariant_EthSolvencyMatchesPendingSellOrders`,
      `invariant_QuoteSolvencyMatchesPendingBuyOrders`, and
      `invariant_NoStrandedRouterAllowance`, each 256 runs / 128,000
      calls / 0 reverts.
- [ ] Fork: `5 passed; 0 failed`.
- [ ] Fuzz: `4 passed; 0 failed` (256 runs each — already counted within
      the unit total above; this run just isolates them).
- [ ] Coverage: `src/OrderKeeper.sol` and `src/DemoUSDC.sol` both 100%
      lines/statements/branches/functions.
- [ ] Plain `forge test` with no flags (fork suite self-skips without
      `--fork-url`): `76 passed; 0 failed; 1 skipped` (`77` total —
      Foundry reports the whole self-skipped fork file as one skipped
      unit, not five).

### `order-indexer/`, `keeper-bot/`, `frontend/`

```shell
cd order-indexer && npm test   # or: cd keeper-bot / cd frontend
```

**Expected results** (as of 2026-08-30):

- [ ] `order-indexer`: `25 passed` (3 test files).
- [ ] `keeper-bot`: `18 passed` (3 test files).
- [ ] `frontend`: `41 passed` (5 test files).

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

The dry run does not update `deployments/sepolia.json`. The script writes
canonical deployment metadata only in Foundry's broadcast or resume context,
after the deployment flow completes.

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

- [ ] `ETHERSCAN_API_KEY` configured in `contracts/.env` as documented by
      `contracts/.env.example`; get one free at https://etherscan.io/apis.
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

## Workflow: Fresh PostgreSQL setup or intentional legacy reset

The current Buy/Sell schema deliberately does not convert rows from the
obsolete per-order `asset` design. Those rows belong to an older contract
deployment and cannot be assigned a truthful Buy/Sell side. Final MVP hosting
therefore starts with a fresh database; the indexer then reconstructs the
current deployment's history from `deployments/sepolia.json`'s
`deploymentBlock`.

### Fresh database for final MacBook deployment

Run these manually before starting the indexer, substituting the intended
database/user names and keeping the real password only in
`order-indexer/.env`:

```shell
createdb --owner=YOUR_POSTGRES_USER orderkeeper
cd order-indexer
npx prisma migrate deploy
npx prisma generate
```

- [ ] `DATABASE_URL` points to the new `orderkeeper` database.
- [ ] `npx prisma migrate status` reports all migrations applied.
- [ ] On first start, the indexer logs that it is backfilling from the
      canonical deployment block rather than from the current chain head.
- [ ] `GET /orders` contains the current deployment's historical orders after
      backfill completes.

### Intentional reset of disposable local development data

This procedure is destructive. Use it only when the database named by the
current `DATABASE_URL` is confirmed to contain disposable development data.
Stop the indexer and keeper first, verify the URL, and then reset explicitly:

```shell
cd order-indexer
grep '^DATABASE_URL=' .env
npx prisma migrate reset --force
npx prisma generate
```

No automatic reset is performed by application startup, tests, or deployment
scripts. Never use this reset procedure against a database whose history must
be retained.

---

## Workflow: Build and prepare MacBook services for PM2

This prepares the repository only. Installing PM2, configuring macOS startup,
and creating a Cloudflare Tunnel remain deliberate manual deployment steps.

```shell
cd order-indexer && npm ci && npm run prisma:generate && npm run build
cd ../keeper-bot && npm ci && npm run build
cd ../frontend && npm ci && npm run build
cd ..
```

Before starting `ecosystem.config.cjs`:

- [ ] Create each service's `.env` from `.env.example` and keep it untracked.
- [ ] Set the frontend's three deployment addresses from the same
      `deployments/sepolia.json` record.
- [ ] Set `VITE_INDEXER_URL` to the public HTTPS API hostname that Cloudflare
      Tunnel will route to `http://127.0.0.1:3001`; Vite embeds this value at
      build time, so rebuild after changing it.
- [ ] Route the frontend hostname to `http://127.0.0.1:4173` and the API
      hostname to `http://127.0.0.1:3001`.
- [ ] Confirm `curl http://127.0.0.1:3001/health` returns `{"status":"ok"}`.

After PM2 is installed manually, start the repository-defined processes with
`pm2 start ecosystem.config.cjs`. Use `pm2 logs`, `pm2 save`, and the macOS
command printed by `pm2 startup` during the deliberate server setup. PM2 keeps
its normal per-process logs under `~/.pm2/logs`; no secrets belong in the
ecosystem file.

---

## Workflow: Continuous deployment to the MacBook

The `Deploy Production` GitHub Actions workflow runs after `CI` completes
successfully for a push or merge to `main`. It uses a dedicated self-hosted
runner on the production Mac, avoiding inbound SSH and Docker. Pull requests,
failed CI runs, other branches, and manual workflow runs do not deploy.

### Required one-time GitHub and server configuration

- [ ] Install a dedicated repository runner manually under the same
      non-administrator macOS account that owns
      `/Users/razs/production/orderkeeper` and the existing PM2 daemon. PM2 is
      per-user, so a different account would not control these applications
      without unsafe cross-user configuration. Never run the runner as root.
- [ ] Register it only to this repository with the labels `self-hosted`,
      `macOS`, and `orderkeeper-production`.
- [ ] Create a GitHub Environment named `production`. Restrict deployment
      branches to `main`; optionally require manual approval for an additional
      safety gate.
- [ ] Protect `main`, require the `CI` checks, restrict who can push/merge, and
      require review for changes under `.github/`.
- [ ] Ensure the runner account has Node 24, npm, Git, curl, PM2, and access to
      the Homebrew PostgreSQL instance used by `DATABASE_URL`.
- [ ] Keep the production checkout on `main` with remote `origin` configured.
- [ ] Confirm that account can fetch `origin` non-interactively using its
      existing read-only deploy key or Git credential. Do not put that
      credential in the repository or workflow.
- [ ] Confirm `order-indexer/.env`, `keeper-bot/.env`, and `frontend/.env`
      already exist inside the production checkout and remain ignored.

No GitHub secrets are required by this design. The runner uses its registered
outbound connection, and all application secrets remain only in the existing
production `.env` files. The workflow does not print, copy, generate, or
overwrite them. `VITE_INDEXER_URL=https://api-orderkeeper.razs.dev` continues
to be loaded by Vite from `frontend/.env` during the production build.

### Deployment sequence

`.github/scripts/deploy-production.sh` performs these fail-fast steps:

1. Verify the production checkout is clean, on `main`, and has all three `.env`
   files.
2. Fetch `origin/main` and fast-forward to the tested commit. It never performs
   an automatic rollback or destructive reset.
3. Run `npm ci`, Prisma generation, and a staged TypeScript build for the
   indexer.
4. Run `npm ci` and a staged TypeScript build for the keeper.
5. Run `npm ci` and a staged Vite production build for the frontend. Vite does
   not empty the bundle currently served by PM2 while this build runs.
6. After every build succeeds, run `npx prisma migrate deploy`.
7. Promote each completed `dist.deploy` directory to `dist`, retaining the
   prior artifact as `dist.previous` for inspection.
8. Run `pm2 startOrReload ecosystem.config.cjs --only <name> --update-env`
   separately for `orderkeeper-indexer`, `orderkeeper-keeper`, and
   `orderkeeper-frontend`. No unrelated PM2 application is addressed.
9. Require successful responses from `http://127.0.0.1:3001/health` and
   `http://127.0.0.1:4173/`.
10. Run `pm2 save` only after both health checks pass.

All dependencies and bundles are prepared while the existing processes remain
running. Prisma production migrations are forward-only and idempotent;
redeploying the same commit safely reruns `npm ci`, builds, and
`prisma migrate deploy` without reapplying completed migrations.

### Manual deployment

From the self-hosted runner account on the Mac, deploy the current tested main
revision with:

```shell
cd /Users/razs/production/orderkeeper
git fetch origin main
bash .github/scripts/deploy-production.sh "$(git rev-parse origin/main)"
```

### Inspecting failures

- Open GitHub Actions → **Deploy Production** and inspect the named failing
  step. The script exits immediately on Git, install, generation, build,
  migration, PM2, or health-check failure.
- On the Mac, inspect only these services with:

```shell
pm2 status
pm2 logs orderkeeper-indexer --lines 200
pm2 logs orderkeeper-keeper --lines 200
pm2 logs orderkeeper-frontend --lines 200
```

Because all builds finish before reload, install/build failures leave the
currently running processes untouched. A migration or later reload failure is
reported but is not automatically reversed.

### Safe rollback

Prefer a Git revert rather than checking out an old detached commit on the
server:

```shell
git checkout main
git pull --ff-only origin main
git revert <bad-commit-sha>
git push origin main
```

The new revert commit passes CI and deploys through the same pipeline. Database
migrations are not automatically rolled back: if a release added an
incompatible migration, create and deploy a forward-fix migration before or
with the code revert. For an urgent application-only rollback, run the same
deployment script against a reviewed revert commit on `main`; never use
`prisma migrate reset` in production.

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

CONTRACT=0x907dC6392df5973aD82816C05E2e15F821054503
WETH=0x1287B650e882514447b96a49a0f8DC1040B26d2A
QUOTE_TOKEN=0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929
# ^ Verify both against the live deployment before running, not just this
#   file — deployments/sepolia.json is the source of truth, and DemoUSDC
#   has no canonical fixed address, so it changes on every redeploy. A
#   stale QUOTE_TOKEN here is exactly what caused the 2026-08-29 Buy-flow
#   bug in frontend/src/config.ts: cast call $CONTRACT
#   "quoteToken()(address)" --rpc-url sepolia to confirm.

# 1. Read the live price first — never guess it.
cast call $CONTRACT "getAssetPrice(address)(uint256)" $WETH --rpc-url sepolia

# 2a. SELL order (deposit ETH, sell when ETH rises). Target comfortably
#     BELOW the live price you just read (GreaterOrEqual, so it's already
#     true and stays true through any realistic movement before keeper-bot
#     picks it up). Replace TARGET_PRICE — e.g. if live price is ~2450e18,
#     use something like 1000000000000000000000 ($1,000).
#     Args: side(0=Sell) condition(0=GTE) targetPrice amount slippageBps expiry
#     For Sell, --value must equal the amount argument.
cast send $CONTRACT \
  "createOrder(uint8,uint8,uint256,uint256,uint256,uint256)" \
  0 \
  0 \
  TARGET_PRICE \
  1000000000000000 \
  3000 \
  $(($(date +%s) + 3600)) \
  --value 0.001ether \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

To create a **BUY** order instead (deposit quoteToken, buy when ETH
falls), approve first — the deposit is pulled with `transferFrom`, so an
un-approved Buy will revert:

```shell
# 2b. BUY order. Two transactions: approve, then create.
#     5000000 = 5 mUSDC (6 decimals).
cast send $QUOTE_TOKEN "approve(address,uint256)" $CONTRACT 5000000 \
  --rpc-url sepolia --private-key $PRIVATE_KEY

#     Target comfortably ABOVE the live price (LessOrEqual = 1, so it's
#     already true). No --value: Buy rejects attached ETH.
cast send $CONTRACT \
  "createOrder(uint8,uint8,uint256,uint256,uint256,uint256)" \
  1 \
  1 \
  TARGET_PRICE \
  5000000 \
  3000 \
  $(($(date +%s) + 3600)) \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

- [ ] Transaction receipt shows `status: 1 (success)`.
- [ ] 3000 bps (30%) slippage is used above, not a realistic order's
      tolerance — this Sepolia pool is shallow and unarbitraged, so the
      actual requirement varies by order size and direction and can
      legitimately range from single-digit percent to this much. See
      README.md's "Accepted MVP slippage tolerance limitation" for why,
      traced from the actual formula and live pool state, and ISSUES.md's
      pool-drift entry for the measurement history. Don't shrink this
      value for a "cleaner" demo without re-checking the live pool first
      — a tighter value can revert unpredictably depending on which way
      the pool has drifted that day.

### Step 4 — Watch `order-indexer` pick it up

```shell
curl -s "http://localhost:3001/orders?status=pending"
```

- [ ] Your new order appears, with `status: "Pending"` and the `side`/
      `targetPrice`/`amount` you just set. If it doesn't appear within a
      few seconds, either `order-indexer` hasn't polled yet, or the
      transaction reverted — reverted transactions emit no event, so a
      missing order can mean "check the transaction on Etherscan," not
      just "check `order-indexer`'s terminal" (see Troubleshooting).

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
      [Sepolia Etherscan](https://sepolia.etherscan.io). What the
      `executeOrder()` transaction shows depends on `side` — the keeper
      fee and swap output are each denominated in whatever the order
      deposited, so they land on opposite legs for Sell vs. Buy:
      - **Sell**: an internal ETH transfer (the keeper fee, to
        `keeper-bot`'s operator address) and a DemoUSDC transfer (the
        swap output, to the order owner).
      - **Buy**: a DemoUSDC transfer (the keeper fee, to `keeper-bot`'s
        operator address) and an internal ETH transfer (the swap output,
        to the order owner).

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
  arbitrage bots trade this testnet pool), and price impact against its
  shallow depth compounds the same way. If the gap exceeds your order's
  `maxSlippageBps`, the swap correctly refuses to execute at a bad price —
  that's the slippage protection working as designed, not a bug. See
  README.md's "Accepted MVP slippage tolerance limitation" for the traced
  mechanism. Either accept a wider `maxSlippageBps` for testing, or add
  more liquidity to rebalance the pool.
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

**Removed 2026-08-29**: this file used to have a "Register additional
price feeds" workflow here, for the four assets (BTC/LINK/USDC/DAI) the
frontend's multi-asset selector once offered. Removed along with that
selector — Milestone 12 was reverted, Milestone 15 replaced it with
bidirectional Buy/Sell on the one WETH/quoteToken pair, and the current
deploy script registers only WETH's feed. See `ROADMAP.md`'s Milestone 12
Outcome note and CLAUDE.md's Design Decisions for why.
