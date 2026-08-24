#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_NAME="ageera-devops"
APP_IMAGE="ageera/devops-assignment-app:local"
NAMESPACE="ageera"
MONITORING_NAMESPACE="monitoring"
CHART_VERSION="87.19.1"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but was not found in PATH." >&2
    exit 1
  }
}

require_cmd docker
require_cmd kind
require_cmd kubectl
require_cmd helm

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running or the current user cannot access it." >&2
  exit 1
fi

echo "==> Creating kind cluster (if needed)"
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --wait 120s
fi

kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

cat <<'MSG'
==> Building application image
MSG
docker build -t "$APP_IMAGE" ./app

echo "==> Loading image into kind"
kind load docker-image "$APP_IMAGE" --name "$CLUSTER_NAME"

echo "==> Deploying application"
kubectl apply -k ./k8s

kubectl rollout status deployment/devops-assignment-app -n "$NAMESPACE" --timeout=180s

echo "==> Adding Prometheus Community Helm repository"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "==> Installing monitoring stack"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE" \
  --create-namespace \
  --version "$CHART_VERSION" \
  --values ./monitoring/kube-prometheus-stack-values.yaml \
  --wait \
  --timeout 10m

echo "==> Waiting for monitoring resources"
kubectl wait --for=condition=Available deployment -l app.kubernetes.io/name=grafana -n "$MONITORING_NAMESPACE" --timeout=180s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus -n "$MONITORING_NAMESPACE" --timeout=180s || true

echo
kubectl get pods -n "$NAMESPACE"
kubectl get pods -n "$MONITORING_NAMESPACE"
echo
cat <<EOF2
Setup complete.

Application:
  kubectl port-forward -n $NAMESPACE svc/devops-assignment-app 3000:3000
  http://127.0.0.1:3000/health
  http://127.0.0.1:3000/ready
  http://127.0.0.1:3000/metrics

Grafana:
  kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-grafana 3001:80
  http://127.0.0.1:3001
  username: admin
  password: admin

Prometheus:
  kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090
  http://127.0.0.1:9090
EOF2
