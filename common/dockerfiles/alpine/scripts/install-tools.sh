#!/bin/bash
set -euo pipefail

# ============================================================
# Dependências básicas
# ============================================================
install_default() {

    echo "📦 Instalando dependências básicas..."

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        wget \
        git \
        jq \
        bash \
        unzip \
        tar \
        gzip \
        gnupg \
        lsb-release

    rm -rf /var/lib/apt/lists/*
}

# ============================================================
# Docker
# ============================================================
install_docker() {

    echo "🐳 Instalando Docker..."

    if command -v docker >/dev/null 2>&1; then

        echo "✅ Docker já instalado:"
        docker --version

        return 0
    fi

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL \
        https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    rm -rf /var/lib/apt/lists/*

    echo "✅ Docker instalado:"
    docker --version

    echo "✅ Docker Buildx:"
    docker buildx version

    echo "✅ Docker Compose:"
    docker compose version
}

# ============================================================
# AWS CLI
# ============================================================
install_aws_cli() {

    echo "☁️ Instalando AWS CLI..."

    if command -v aws >/dev/null 2>&1; then

        echo "✅ AWS CLI já instalada:"
        aws --version

        return 0
    fi

    curl -fsSL \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o /tmp/awscliv2.zip

    unzip -q \
        /tmp/awscliv2.zip \
        -d /tmp

    /tmp/aws/install

    rm -rf \
        /tmp/aws \
        /tmp/awscliv2.zip

    echo "✅ AWS CLI instalada:"
    aws --version
}

# ============================================================
# kubectl
# ============================================================
install_kubectl() {

    echo "☸️ Instalando kubectl..."

    KUBECTL_VERSION="${KUBECTL_VERSION:-$(curl -fsSL \
        https://dl.k8s.io/release/stable.txt)}"

    echo "✅ kubectl versão: $KUBECTL_VERSION"

    curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl

    chmod +x /usr/local/bin/kubectl

    echo "✅ kubectl instalado:"
    kubectl version --client
}

# ============================================================
# Azure DevOps Agent
# ============================================================
install_azuredevops_agent() {

    echo "🤖 Instalando Azure DevOps Agent..."

    mkdir -p /opt/az-agent

    cd /opt/az-agent

    AZP_AGENT_VERSION="${AZP_AGENT_VERSION:-$(curl -fsSL \
        https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest \
        | jq -r .tag_name \
        | sed 's/^v//')}"

    echo "✅ Azure DevOps Agent versão: $AZP_AGENT_VERSION"

    AGENT_PACKAGE="vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz"

    wget -q \
        "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/${AGENT_PACKAGE}" \
        -O "$AGENT_PACKAGE"

    tar -zxvf "$AGENT_PACKAGE"

    ./bin/installdependencies.sh

    rm -f "$AGENT_PACKAGE"

    echo "✅ Azure DevOps Agent instalado."
}

# ============================================================
# Helm
# ============================================================
validate_helm() {

    echo "⎈ Validando Helm compilado..."

    if [[ ! -x /usr/local/bin/helm ]]; then

        echo "❌ Helm não encontrado."

        exit 1
    fi

    echo "✅ Helm:"
    helm version

    echo
    echo "🔎 Localização:"
    command -v helm

    echo
    echo "🔎 Arquivo:"
    ls -lh /usr/local/bin/helm
}

# ============================================================
# Node.js 22
# ============================================================
install_nodejs() {

    echo "🟢 Instalando Node.js 22..."

    if command -v node >/dev/null 2>&1; then

        echo "Node já instalado:"
        node --version

        return 0
    fi

    curl -fsSL \
        https://deb.nodesource.com/setup_22.x \
        | bash -

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nodejs

    echo "✅ Node.js:"
    node --version

    echo "✅ npm:"
    npm --version
}

# ============================================================
# Yarn
# ============================================================
install_yarn() {

    echo "🧶 Instalando Yarn via Corepack..."

    if ! command -v corepack >/dev/null 2>&1; then

        echo "Corepack não encontrado. Instalando..."

        npm install -g corepack
    fi

    corepack enable

    echo "✅ Corepack:"
    corepack --version

    echo "✅ Yarn:"
    yarn --version
}

# ============================================================
# Python 3.10 / 3.11
# ============================================================
install_python() {

    echo "🐍 Instalando Python 3.10 e 3.11..."

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        software-properties-common

    add-apt-repository -y ppa:deadsnakes/ppa

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3.10 \
        python3.10-venv \
        python3.11 \
        python3.11-venv 

    echo "✅ Python 3.10:"
    python3.10 --version

    echo "✅ Python 3.11:"
    python3.11 --version
}

# ============================================================
# Execução
# ============================================================
install_default
install_docker
install_aws_cli
install_nodejs
install_yarn
install_python
install_kubectl
validate_helm
install_azuredevops_agent


# ============================================================
# Resumo
# ============================================================
echo
echo "=========================================="
echo "✅ Instalação concluída"
echo "=========================================="

echo
echo "Docker:"
docker --version

echo
echo "Docker Buildx:"
docker buildx version

echo
echo "Docker Compose:"
docker compose version

echo
echo "AWS CLI:"
aws --version

echo
echo "kubectl:"
kubectl version --client

echo
echo "Helm:"
helm version

echo
echo "Azure DevOps Agent:"
echo "${AZP_AGENT_VERSION:-latest}"