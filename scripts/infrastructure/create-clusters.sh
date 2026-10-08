#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
export KIND_EXPERIMENTAL_PROVIDER=podman
image='docker.io/kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed'
for name in dev qa prd; do
  if ! kind get clusters | grep -qx "$name"; then
    kind create cluster --name "$name" --image "$image" --wait 120s
  fi
  podman update --restart=unless-stopped "$name-control-plane"
done
"$(dirname "$0")/configure-clusters.sh"
