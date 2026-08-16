# Deployments

Deployed contract addresses per chain/environment, per `CLAUDE.md`'s
Planned Structure. One JSON file per target, e.g. `sepolia.json`:

```json
{
  "chainId": 11155111,
  "OrderKeeper": "0x...",
  "deployedAt": "2026-XX-XX",
  "deployerTx": "0x..."
}
```

Empty until `contracts/` has something to deploy. Populated by the
`deploy` skill (`.claude/skills/deploy/`) once it's filled in.
