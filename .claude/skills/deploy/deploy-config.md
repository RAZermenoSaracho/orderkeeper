# Deploy Config (stub)

Placeholder for deployment target configuration, referenced by
[SKILL.md](SKILL.md). Empty until `contracts/` exists.

## Expected shape (not yet real)

Per environment, this should eventually record — non-secret values only,
everything secret stays in `.env` per `.claude/rules/security.md`:

- Chain name / chain ID
- Chainlink feed address(es) in use
- Uniswap router address in use
- Where the deployed contract address gets recorded (`deployments/`, per
  `CLAUDE.md`)

No environments are defined yet.
