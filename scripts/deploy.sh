#!/bin/sh
set -eu
test "$#" -eq 3 || { echo "Usage: $0 <context> <overlay> <image>" >&2; exit 2; }
CONTEXT=${1:?context required}
OVERLAY=${2:?overlay required}
IMAGE=${3:?image required}
case "$CONTEXT:$OVERLAY" in kind-dev:dev|kind-qa:qa|kind-prd:prd) ;; *) echo 'Context/overlay mismatch' >&2; exit 2;; esac
case "$IMAGE" in localhost:5000/minimal-api:git-*) ;; *) echo 'Expected a Git-tagged local image' >&2; exit 2;; esac
test -d "k8s/overlays/$OVERLAY" || { echo "Overlay not found" >&2; exit 1; }
kubectl config get-contexts "$CONTEXT" >/dev/null
kubectl --context "$CONTEXT" get --raw=/readyz >/dev/null
kubectl --context "$CONTEXT" get namespace minimal-api >/dev/null
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT
kubectl kustomize "k8s/overlays/$OVERLAY" | sed "s|localhost:5000/minimal-api:placeholder|$IMAGE|g" > "$rendered"
kubectl --context "$CONTEXT" -n minimal-api apply -f "$rendered"
kubectl --context "$CONTEXT" -n minimal-api set env deployment/api BEHAVIOR_REGRESSION=false
kubectl --context "$CONTEXT" -n minimal-api rollout status deployment/postgres --timeout=180s
job="migration"
kubectl --context "$CONTEXT" -n minimal-api delete job "$job" --ignore-not-found --wait=true
cat <<EOF | kubectl --context "$CONTEXT" -n minimal-api apply -f -
apiVersion: batch/v1
kind: Job
metadata: {name: $job}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 170
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migration
          image: $IMAGE
          args: [migrate]
          env:
            - {name: FAIL_MIGRATION, value: '${FAIL_MIGRATION:-0}'}
            - {name: DOTNET_USE_POLLING_FILE_WATCHER, value: '1'}
            - name: ConnectionStrings__Todos
              valueFrom: {secretKeyRef: {name: postgres-credentials, key: connectionString}}
EOF
if ! kubectl --context "$CONTEXT" -n minimal-api wait --for=condition=complete "job/$job" --timeout=180s; then
  kubectl --context "$CONTEXT" -n minimal-api logs "job/$job" || true
  exit 1
fi
kubectl --context "$CONTEXT" -n minimal-api logs "job/$job" --all-containers=true
if [ "${FAIL_READINESS:-0}" = 1 ]; then
  kubectl --context "$CONTEXT" -n minimal-api patch deployment api --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/invalid-readiness"}]'
fi
kubectl --context "$CONTEXT" -n minimal-api rollout status deployment/api --timeout=180s
kubectl --context "$CONTEXT" -n minimal-api get deployment api -o jsonpath='{.spec.template.spec.containers[0].image}'
printf '\n'
