#!/usr/bin/env bash
set -euo pipefail

podman run -d \
  --name build-agent \
  --replace \
  --network jenkins \
  --restart=unless-stopped \
  --security-opt label=disable \
  --userns=keep-id \
  -v ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock:/run/podman/podman.sock \
  -v podman_node_home:/home/jenkins/agent \
  --secret build_agent_secret,type=mount \
  -e JENKINS_URL=http://jenkins:8080/ \
  -e JENKINS_AGENT_NAME=build-agent \
  -e JENKINS_AGENT_WORKDIR=/home/jenkins/agent \
  -e JENKINS_WEB_SOCKET=true \
  -e CONTAINER_HOST=unix:///run/podman/podman.sock \
  --entrypoint /bin/sh \
  localhost/build-agent-img:latest \
  -c 'export JENKINS_SECRET="$(tr -d "\r\n" < /run/secrets/build_agent_secret)"; exec /usr/local/bin/jenkins-agent'
