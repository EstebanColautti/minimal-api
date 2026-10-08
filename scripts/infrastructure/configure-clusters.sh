#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
podman network connect kind registry 2>/dev/null || true
podman network connect kind deploy-agent 2>/dev/null || true
config="$HOME/.kube/deploy-config"
: > "$config"
chmod 600 "$config"
for env in dev qa prd; do
  context="kind-$env"
  node="$env-control-plane"
  podman exec "$node" mkdir -p /etc/containerd/certs.d/localhost:5000
  printf 'server = "http://registry:5000"\n[host."http://registry:5000"]\n  capabilities = ["pull", "resolve"]\n' | podman exec -i "$node" sh -c 'cat > /etc/containerd/certs.d/localhost:5000/hosts.toml'
  kubectl --context "$context" create namespace minimal-api --dry-run=client -o yaml | kubectl --context "$context" apply -f -
  password=$(head -c 24 /dev/urandom | base64 | tr -d '\n')
  if ! kubectl --context "$context" -n minimal-api get secret postgres-credentials >/dev/null 2>&1; then
    kubectl --context "$context" -n minimal-api create secret generic postgres-credentials \
      --from-literal=username=todos --from-literal=password="$password" \
      --from-literal=connectionString="Host=postgres;Database=todos;Username=todos;Password=$password"
  fi
  cat <<'EOF' | kubectl --context "$context" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata: {name: jenkins-deployer, namespace: minimal-api}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: jenkins-deployer, namespace: minimal-api}
rules:
  - apiGroups: ['', apps, batch]
    resources: [configmaps, services, persistentvolumeclaims, pods, deployments, replicasets, jobs]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: ['']
    resources: [pods/log, events]
    verbs: [get, list, watch]
  - apiGroups: ['']
    resources: [pods/portforward]
    verbs: [create]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: jenkins-deployer, namespace: minimal-api}
subjects: [{kind: ServiceAccount, name: jenkins-deployer, namespace: minimal-api}]
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: jenkins-deployer}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: jenkins-namespace-reader}
rules:
  - nonResourceURLs: ["/readyz"]
    verbs: [get]
  - apiGroups: ['']
    resources: [namespaces]
    resourceNames: [minimal-api]
    verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: jenkins-namespace-reader}
subjects: [{kind: ServiceAccount, name: jenkins-deployer, namespace: minimal-api}]
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: jenkins-namespace-reader}
---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: minimal-api
  annotations: {kubernetes.io/service-account.name: jenkins-deployer}
type: kubernetes.io/service-account-token
EOF
  for attempt in $(seq 1 20); do
    token=$(kubectl --context "$context" -n minimal-api get secret jenkins-deployer-token -o jsonpath='{.data.token}' | base64 -d)
    test -n "$token" && break
    sleep 1
  done
  ca=$(mktemp)
  kubectl config view --context "$context" --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$ca"
  kubectl --kubeconfig "$config" config set-cluster "$context" --server="https://$node:6443" --tls-server-name=localhost --certificate-authority="$ca" --embed-certs=true >/dev/null
  kubectl --kubeconfig "$config" config set-credentials "deploy-$env" --token="$token" >/dev/null
  kubectl --kubeconfig "$config" config set-context "$context" --cluster="$context" --user="deploy-$env" --namespace=minimal-api >/dev/null
  rm -f "$ca"
done
podman exec deploy-agent kubectl --context kind-dev auth can-i patch deployments -n minimal-api
podman exec deploy-agent kubectl --context kind-dev auth can-i create namespaces || true
