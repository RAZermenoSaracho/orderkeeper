#!/usr/bin/env bash
#
# PreToolUse hook (matcher: Bash). Runs before every Bash tool call.
#
# Scans currently staged changes (git diff --cached) for obvious
# hardcoded-secret patterns and blocks the tool call if any are found.
# This is a backstop for security.md rule (a) — not a substitute for not
# hardcoding secrets in the first place. It will not catch every pattern.
#
# Claude Code PreToolUse hook contract: exit 0 = allow, exit 2 = block
# (stderr is surfaced back to the model/user as the block reason).

set -euo pipefail

# Not inside a git repo, or no git available — nothing to scan, allow.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

STAGED_DIFF="$(git diff --cached --diff-filter=ACM -U0 2>/dev/null || true)"

if [ -z "$STAGED_DIFF" ]; then
  exit 0
fi

# Only inspect added lines, not removed ones.
ADDED_LINES="$(printf '%s\n' "$STAGED_DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+' || true)"

if [ -z "$ADDED_LINES" ]; then
  exit 0
fi

FOUND=""

check_pattern() {
  local label="$1"
  local pattern="$2"
  local match
  match="$(printf '%s\n' "$ADDED_LINES" | grep -EnIi -- "$pattern" || true)"
  if [ -n "$match" ]; then
    FOUND="${FOUND}\n[$label]\n${match}\n"
  fi
}

# Raw EVM private key (32 bytes hex, optionally 0x-prefixed).
check_pattern "possible raw private key" '(^|[^0-9a-fA-F])0x[0-9a-fA-F]{64}([^0-9a-fA-F]|$)'

# PEM-style private key block.
check_pattern "PEM private key header" '-----BEGIN [A-Z ]*PRIVATE KEY-----'

# AWS access key id.
check_pattern "AWS access key id" 'AKIA[0-9A-Z]{16}'

# Generic "<secret-ish name> = <long literal>" assignment, e.g.
# apiKey = "...", PRIVATE_KEY: '...', secret_token=...
check_pattern "generic secret-like assignment" \
  '(api[_-]?key|apikey|secret|private[_-]?key|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*['\''"][A-Za-z0-9_/+=-]{16,}['\''"]'

# RPC URL with an embedded provider API key (Alchemy/Infura-style path).
check_pattern "RPC URL with embedded key" \
  'https?://[^[:space:]]*(alchemy|infura)[^[:space:]]*/(v2|v3)/[A-Za-z0-9_-]{16,}'

if [ -n "$FOUND" ]; then
  {
    echo "BLOCKED: possible hardcoded secret in staged changes."
    echo "Per .claude/rules/security.md rule (a), secrets must come from"
    echo "environment variables via .env, never be committed as literals."
    echo ""
    echo -e "$FOUND"
    echo "If this is a false positive, unstage the file or replace the"
    echo "literal with an environment variable reference before retrying."
  } >&2
  exit 2
fi

exit 0
