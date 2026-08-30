#!/usr/bin/env bash

set -Eeuo pipefail

readonly PRODUCTION_DIR="${ORDERKEEPER_PRODUCTION_DIR:-/Users/razs/production/orderkeeper}"
readonly REQUESTED_SHA="${1:-}"
readonly PM2_CONFIG="$PRODUCTION_DIR/ecosystem.config.cjs"

fail() {
  echo "Deployment failed: $*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  echo "Deployment failed at line $1 (exit $exit_code). Existing PM2 processes were not intentionally stopped." >&2
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

[[ "$REQUESTED_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "expected a full 40-character commit SHA"
[[ -d "$PRODUCTION_DIR/.git" ]] || fail "$PRODUCTION_DIR is not a Git checkout"

for command in git npm npx pm2 curl; do
  command -v "$command" >/dev/null || fail "required command is unavailable: $command"
done

cd "$PRODUCTION_DIR"

[[ "$(git branch --show-current)" == "main" ]] || fail "production checkout must be on main"
git diff --quiet || fail "production checkout has unstaged tracked changes"
git diff --cached --quiet || fail "production checkout has staged changes"

for env_file in order-indexer/.env keeper-bot/.env frontend/.env; do
  [[ -f "$env_file" ]] || fail "required production environment file is missing: $env_file"
done

echo "Fetching main from origin..."
git fetch --prune origin main
git cat-file -e "$REQUESTED_SHA^{commit}" 2>/dev/null || fail "requested commit was not fetched from origin"
git merge-base --is-ancestor "$REQUESTED_SHA" origin/main \
  || fail "requested commit is not part of origin/main"

current_sha="$(git rev-parse HEAD)"
if [[ "$current_sha" == "$REQUESTED_SHA" ]]; then
  echo "Production already points to $REQUESTED_SHA; rebuilding idempotently."
elif git merge-base --is-ancestor "$current_sha" "$REQUESTED_SHA"; then
  git merge --ff-only "$REQUESTED_SHA"
elif git merge-base --is-ancestor "$REQUESTED_SHA" "$current_sha"; then
  fail "production is already ahead of $REQUESTED_SHA at $current_sha; refusing to deploy a different revision"
else
  fail "production main has diverged from the requested commit"
fi

echo "Installing dependencies and building order-indexer..."
(
  cd order-indexer
  npm ci
  npm run prisma:generate
  rm -rf dist.deploy
  npx tsc --outDir dist.deploy
)

echo "Installing dependencies and building keeper-bot..."
(
  cd keeper-bot
  npm ci
  rm -rf dist.deploy
  npx tsc --outDir dist.deploy
)

echo "Installing dependencies and building frontend..."
(
  cd frontend
  npm ci
  rm -rf dist.deploy
  npx tsc -b
  npx vite build --outDir dist.deploy
)

echo "Applying production database migrations..."
(
  cd order-indexer
  npx prisma migrate deploy
)

promote_build() {
  local service_dir="$1"

  [[ -d "$service_dir/dist.deploy" ]] || fail "build output is missing: $service_dir/dist.deploy"
  rm -rf "$service_dir/dist.previous"
  if [[ -d "$service_dir/dist" ]]; then
    mv "$service_dir/dist" "$service_dir/dist.previous"
  fi
  mv "$service_dir/dist.deploy" "$service_dir/dist"
}

echo "Promoting completed build artifacts..."
promote_build order-indexer
promote_build keeper-bot
promote_build frontend

echo "Reloading only OrderKeeper PM2 applications..."
for app in orderkeeper-indexer orderkeeper-keeper orderkeeper-frontend; do
  pm2 startOrReload "$PM2_CONFIG" --only "$app" --update-env
done

health_check() {
  local service="$1"
  local url="$2"

  if ! curl --fail --silent --show-error --retry 10 --retry-delay 2 \
    --retry-connrefused --retry-all-errors --max-time 5 "$url" >/dev/null; then
    fail "$service health check failed: $url"
  fi
  echo "$service health check passed: $url"
}

health_check "order-indexer" "http://127.0.0.1:3001/health"
health_check "frontend" "http://127.0.0.1:4173/"

pm2 save
echo "Deployment completed successfully at $(git rev-parse HEAD)."
