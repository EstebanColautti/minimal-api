#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.kube"
touch "$HOME/.kube/deploy-config"
chmod 600 "$HOME/.kube/deploy-config"
if ! podman secret inspect deploy_agent_secret >/dev/null 2>&1; then
  podman exec jenkins cat /var/jenkins_home/deploy-agent-secret | podman secret create deploy_agent_secret - >/dev/null
fi
podman run -d --name deploy-agent --replace --network jenkins --restart=unless-stopped \
  --security-opt label=disable --userns=keep-id \
  -v "$HOME/.kube/deploy-config:/home/jenkins/kubeconfig:ro" \
  -v jenkins_deploy_agent_home:/home/jenkins/agent \
  --secret deploy_agent_secret,type=mount \
  -e KUBECONFIG=/home/jenkins/kubeconfig \
  -e JENKINS_URL=http://jenkins:8080/ -e JENKINS_AGENT_NAME=deploy-agent \
  -e JENKINS_AGENT_WORKDIR=/home/jenkins/agent -e JENKINS_WEB_SOCKET=true \
  --entrypoint /bin/sh localhost/deploy-agent-img:latest \
  -c 'export JENKINS_SECRET="$(cat /run/secrets/deploy_agent_secret)"; exec /usr/local/bin/jenkins-agent'

podman network connect kind deploy-agent
