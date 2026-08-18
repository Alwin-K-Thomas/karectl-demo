#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/versions.env"

say() { echo "=== $* ==="; }
mkdir -p /home/vscode/.kube
until [ -f /kubeconfig/kubeconfig.yaml ]; do sleep 2; done
sed 's|127\.0\.0\.1|k3s-server|g' /kubeconfig/kubeconfig.yaml > /home/vscode/.kube/config
chmod 600 /home/vscode/.kube/config
export KUBECONFIG=/home/vscode/.kube/config
echo "export KUBECONFIG=/home/vscode/.kube/config" >> /home/vscode/.bashrc

say "Get API server"
until kubectl version >/dev/null 2>&1; do sleep 2; done
kubectl get nodes

say "Setup Gateway API ${GATEWAY_API_VERSION} CRDs"
kubectl apply --server-side --force-conflicts -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"

say "Setup Cilium ${CILIUM_VERSION}"
if ! kubectl -n kube-system get daemonset cilium >/dev/null 2>&1; then
  cilium install \
    --version "${CILIUM_VERSION}" \
    --set operator.replicas=1 \
    --set kubeProxyReplacement=false \
    --set nodePort.enabled=true \
    --set gatewayAPI.enabled=true \
    --set ipam.operator.clusterPoolIPv4PodCIDRList='{10.42.0.0/16}'
fi

say "Waiting for Cilium"
cilium status --wait --wait-duration 5m
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl wait --for=condition=Accepted gatewayclass/cilium --timeout=300s

if [ -S /var/run/docker.sock ]; then
  SOCK_GID="$(stat -c '%g' /var/run/docker.sock)"
  if ! getent group "${SOCK_GID}" >/dev/null 2>&1; then
    if getent group docker >/dev/null 2>&1; then
      sudo groupmod -g "${SOCK_GID}" docker
    else
      sudo groupadd -g "${SOCK_GID}" docker
    fi
  fi
  GROUP_NAME="$(getent group "${SOCK_GID}" | cut -d: -f1)"
  if ! id -nG vscode | tr ' ' '\n' | grep -qx "${GROUP_NAME}"; then
    sudo usermod -aG "${GROUP_NAME}" vscode
  fi
  say "vscode is in group ${GROUP_NAME} (gid ${SOCK_GID}) for docker.sock access"
else
  echo "WARNING: /var/run/docker.sock not present — skipping docker group setup (only Task 10 needs this)" >&2
fi
