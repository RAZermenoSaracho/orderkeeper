---
name: deploy
description: Deploy OrderKeeper contracts to a target chain/environment. STUB — not yet functional; contracts/ doesn't exist yet.
---

# Deploy (stub)

This skill is a placeholder. It will drive contract deployment once
`contracts/` exists — currently there is nothing to deploy.

## When this will be used

Once `contracts/` has a working Foundry project, this skill should:

1. Read target chain/environment config from `deploy-config.md` (see that
   file — also a stub right now).
2. Run the appropriate `forge script` deployment script against the target
   RPC (`$RPC_URL` from the deployer's `.env` — never a hardcoded key or
   URL, per `.claude/rules/security.md`).
3. Record the deployed address(es) under `deployments/` per chain/
   environment, as described in `CLAUDE.md`.
4. Verify the contract on the relevant block explorer, if supported.

## Not yet defined

- Which chains/environments are actually targeted beyond Sepolia.
- Whether deployment is a single script or per-contract scripts.
- Post-deploy verification steps.

Fill this in when `contracts/` is scaffolded.
