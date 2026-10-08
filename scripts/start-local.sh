#!/bin/sh
set -eu
for container in dev-control-plane qa-control-plane prd-control-plane registry scm jenkins build-agent deploy-agent; do
    podman start "$container"
done
echo 'Open http://localhost:8080/job/minimal-api/'
