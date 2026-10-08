#!/bin/sh
set -eu
URL=${1:?URL required}
curl -fsS "$URL/health/ready" >/dev/null
curl -fsS "$URL/todos" | grep -q '^\['
if [ "${2:-}" = --read-only ]; then
  echo 'Read-only smoke test passed'
  exit 0
fi
title="pipeline-smoke-$(date +%s)-$$"
response=$(curl -fsS -H 'Content-Type: application/json' -d "{\"title\":\"$title\"}" "$URL/todos")
id=$(printf '%s' "$response" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
test -n "$id"
trap 'curl -fsS -X DELETE "$URL/todos/$id" >/dev/null || true' EXIT
received=$(curl -fsS "$URL/todos/$id")
printf '%s' "$received" | grep -q "\"title\":\"$title\""
printf '%s' "$received" | grep -q '"isComplete":false'
test "${FAIL_SMOKE:-0}" != 1
echo 'Write/read smoke test passed'
