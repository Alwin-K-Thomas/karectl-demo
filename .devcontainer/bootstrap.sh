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

say "Setup Cilium ${CILIUM_VERSION}"
if ! kubectl -n kube-system get daemonset cilium >/dev/null 2>&1; then
  cilium install \
    --version "${CILIUM_VERSION}" \
    --set operator.replicas=1 \
    --set kubeProxyReplacement=true \
    --set ipam.operator.clusterPoolIPv4PodCIDRList='{10.42.0.0/16}'
fi

say "Waiting for Cilium"
cilium status --wait --wait-duration 5m
kubectl wait --for=condition=Ready node --all --timeout=300s

say "Traefik setup"
kubectl -n kube-system rollout status deploy/traefik --timeout=300s

say "Installing Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd apply --server-side --force-conflicts -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p \
  '{"data":{"server.insecure":"true","server.rootpath":"/argocd"}}'
kubectl -n argocd patch configmap argocd-cm --type merge -p \
  '{"data":{"kustomize.buildOptions":"--enable-helm"}}'
kubectl -n argocd rollout restart deploy argocd-server argocd-repo-server
kubectl -n argocd rollout status deploy argocd-server --timeout=300s
kubectl -n argocd rollout status deploy argocd-repo-server --timeout=300s

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /argocd
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

say "Configmap setup"
if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
  DOMAIN="${DOMAIN:-${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}}"
fi
if [ -n "${DOMAIN:-}" ]; then
  kubectl create namespace keycloak   --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace jupyterhub --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n keycloak   create configmap cluster-domain --from-literal=DOMAIN="${DOMAIN}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n jupyterhub create configmap cluster-domain --from-literal=DOMAIN="${DOMAIN}" --dry-run=client -o yaml | kubectl apply -f -
  say "DOMAIN resolved to ${DOMAIN}"
else
  echo "DOMAIN could not be resolved"
fi

say "Setup root app"
kubectl apply -f "${HERE}/../gitops/root-app.yaml"

echo "URL:  https://${DOMAIN:-<DOMAIN>}/argocd"
echo "user: admin"
echo -n "pass: "; kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

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
