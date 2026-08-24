#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_NAME="ageera-devops"

helm uninstall kube-prometheus-stack -n monitoring >/dev/null 2>&1 || true
kubectl delete namespace ageera --ignore-not-found >/dev/null 2>&1 || true
kubectl delete namespace monitoring --ignore-not-found >/dev/null 2>&1 || true
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

echo "Cluster '$CLUSTER_NAME' and assignment resources removed."
