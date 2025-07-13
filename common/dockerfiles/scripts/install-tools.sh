install_default(){
    apk add --no-cache git jq aws-cli curl wget bash
}

install_azuredevops_agent(){
    cd /opt/az-agent
    LATEST_VERSION=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r .tag_name | sed 's/^v//')

    echo "✅ Mais nova: $LATEST_VERSION"
    wget https://download.agent.dev.azure.com/agent/$LATEST_VERSION/vsts-agent-linux-musl-x64-$LATEST_VERSION.tar.gz
    tar zxvf vsts-agent-linux-musl-x64-$LATEST_VERSION.tar.gz
    ./bin/installdependencies.sh
    rm vsts-agent-linux-musl-x64-$LATEST_VERSION.tar.gz
}

install_default
install_azuredevops_agent