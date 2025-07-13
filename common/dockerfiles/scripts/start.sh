#!/bin/bash
set -euo pipefail

# === Configurações de cor ===
nocolor="\033[0m"
lightcyan="\033[1;36m"
red="\033[0;31m"
green="\033[0;32m"

print_header() {
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

error() {
  echo -e "${red}❌ error:${nocolor} $1" >&2
}

success() {
  echo -e "${green}✅${nocolor} $1"
}

# === Flags globais de controle ===
AGENT_CONFIGURED=false

# === Função de limpeza ==
cleanup() {
  echo
  print_header "🧹 Executando cleanup..."

  if [[ "$AGENT_CONFIGURED" = true && -e ./config.sh ]]; then
    echo "🔧 Removendo agente Azure Pipelines..."

    until ./config.sh remove \
      --unattended \
      --auth "SP" \
      --clientid "$CLIENT_ID" \
      --clientsecret "$CLIENT_SECRET" \
      --tenantid "$TENANT_ID"; do
        echo "⚠️ Falha ao remover agente. Retentando em 10 segundos..."
        sleep 10
    done

    success "Agente removido com sucesso!"
  else
    echo "ℹ️ Agente não foi configurado ou já removido."
  fi
}

# === Traps para garantir cleanup em qualquer caso ===
trap 'cleanup' EXIT
trap 'echo "🛑 Sinal SIGINT recebido"; exit 130' INT
trap 'echo "🛑 Sinal SIGTERM recebido"; exit 143' TERM
trap 'error "Erro em linha $LINENO"; exit 1' ERR

# === Verifica variáveis obrigatórias ===
required_env_vars=("SECRETNAME" "AWS_REGION" "AZP_URL" "AZP_POOL")

for var in "${required_env_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    error "Variável de ambiente obrigatória ausente: $var"
    exit 1
  fi
done

dockerd&

su azp

# === Busca o Secret do AWS Secrets Manager ===
print_header "🔐 Buscando segredo no AWS Secrets Manager..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRETNAME" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.azuredevopsclientid // empty')
CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.azuredevopsclientsecret // empty')
TENANT_ID=$(echo "$SECRET_JSON" | jq -r '.azuredevopstenantid // empty')

missing=0
[[ -z "$CLIENT_ID" ]] && error "Faltando: azuredevopsclientid" && missing=1 || success "Encontrado: azuredevopsclientid"
[[ -z "$CLIENT_SECRET" ]] && error "Faltando: azuredevopsclientsecret" && missing=1 || success "Encontrado: azuredevopsclientsecret"
[[ -z "$TENANT_ID" ]] && error "Faltando: azuredevopstenantid" && missing=1 || success "Encontrado: azuredevopstenantid"

if [[ "$missing" -eq 1 ]]; then
  error "Abortando: campos obrigatórios ausentes no secret"
  exit 1
fi

# === Prepara diretório de trabalho ===
if [[ -n "${AZP_WORK:-}" ]]; then
  mkdir -p "$AZP_WORK"
fi

# === Configura o agente ===
print_header "⚙️  Configurando agente Azure Pipelines..."

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "$AZP_URL" \
  --auth "SP" \
  --clientid "$CLIENT_ID" \
  --clientsecret "$CLIENT_SECRET" \
  --tenantid "$TENANT_ID" \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula

AGENT_CONFIGURED=true

# === Executa o agente em modo --once ===
print_header "🚀 Executando agente em modo --once..."

chmod +x ./run.sh
./run.sh --once "$@"