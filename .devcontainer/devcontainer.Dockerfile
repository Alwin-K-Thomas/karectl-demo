FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG KUBECTL_VERSION=v1.31.5
ARG HELM_VERSION=v3.16.3
ARG CILIUM_CLI_VERSION=v0.16.22
ARG ARGOCD_CLI_VERSION=v3.0.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates jq gettext-base \
 && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
 && curl -sfLo kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && curl -sfLo kubectl.sha256 \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
 && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - \
 && install -m 0755 kubectl /usr/local/bin/kubectl \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
 && curl -sfLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" \
 && sha256sum -c "helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" \
 && tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" \
 && install -m 0755 linux-amd64/helm /usr/local/bin/helm \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLO "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz" \
 && curl -sfLO "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz.sha256sum" \
 && sha256sum -c cilium-linux-amd64.tar.gz.sha256sum \
 && tar -xzf cilium-linux-amd64.tar.gz -C /usr/local/bin cilium \
 && chmod +x /usr/local/bin/cilium \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLo argocd-linux-amd64 \
      "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argocd-linux-amd64" \
 && curl -sfLo cli_checksums.txt \
      "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/cli_checksums.txt" \
 && grep "  argocd-linux-amd64$" cli_checksums.txt | sha256sum -c - \
 && install -m 0755 argocd-linux-amd64 /usr/local/bin/argocd \
 && cd / && rm -rf /tmp/*

RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli \
 && rm -rf /var/lib/apt/lists/*

USER vscode
