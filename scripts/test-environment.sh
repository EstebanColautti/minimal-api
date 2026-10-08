#!/bin/sh
set -eu
context=${1:?context}
port=${2:?port}
shift 2
log=$(mktemp)
kubectl --context "$context" -n minimal-api port-forward service/api "$port:8080" > "$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"' EXIT
count=0
until curl -fsS "http://localhost:$port/health/ready" >/dev/null 2>&1; do
  count=$((count+1)); test "$count" -lt 30 || { cat "$log"; exit 1; }
  sleep 1
done
./scripts/smoke-test.sh "http://localhost:$port" "$@"
