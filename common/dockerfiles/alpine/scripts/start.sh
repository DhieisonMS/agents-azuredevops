#!/bin/bash
set -euo pipefail

export AGENT_ALLOW_RUNASROOT=1
# ============================================================
# Configurações
# ============================================================
nocolor="\033[0m"
lightcyan="\033[1;36m"
red="\033[0;31m"
green="\033[0;32m"
yellow="\033[0;33m"

print_header() {
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

error() {
  echo -e "${red}❌ error:${nocolor} $1" >&2
}

success() {
  echo -e "${green}✅${nocolor} $1"
}

warning() {
  echo -e "${yellow}⚠️${nocolor} $1"
}

# ============================================================
# Variáveis
# ============================================================
AGENT_CONFIGURED=false
CLEANUP_DONE=false

AZP_AUTH="${AZP_AUTH:-SP}"
AZP_AGENT_NAME="${AZP_AGENT_NAME:-$(hostname)}"
AZP_WORK="${AZP_WORK:-_work}"

AZP_CLIENT_ID="${AZP_CLIENT_ID:-}"
AZP_CLIENT_SECRET="${AZP_CLIENT_SECRET:-}"
AZP_TENANT_ID="${AZP_TENANT_ID:-}"
AZP_TOKEN="${AZP_TOKEN:-}"

DOCKER_PID=""
AGENT_PID=""

# ============================================================
# Cleanup
# ============================================================
cleanup() {

  # Evita executar cleanup mais de uma vez
  if [[ "$CLEANUP_DONE" == true ]]; then
    return 0
  fi

  CLEANUP_DONE=true

  echo
  print_header "🧹 Executando cleanup..."

  # ----------------------------------------------------------
  # Para o agente
  # ----------------------------------------------------------
  if [[ -n "${AGENT_PID:-}" ]]; then

    if kill -0 "$AGENT_PID" 2>/dev/null; then

      echo "🛑 Encerrando processo do Azure Pipelines Agent..."

      kill -TERM "$AGENT_PID" 2>/dev/null || true

      # Aguarda até 10 segundos pelo encerramento
      for i in {1..10}; do

        if ! kill -0 "$AGENT_PID" 2>/dev/null; then
          break
        fi

        sleep 1

      done

      # Se ainda estiver executando, força encerramento
      if kill -0 "$AGENT_PID" 2>/dev/null; then

        warning "Agente não encerrou após 10 segundos."
        warning "Forçando encerramento do processo."

        kill -KILL "$AGENT_PID" 2>/dev/null || true

      fi

    fi

  fi

  # ----------------------------------------------------------
  # Remove o agente do Azure DevOps
  # ----------------------------------------------------------
  if [[ "$AGENT_CONFIGURED" != true ]]; then

    echo "ℹ️ Agente não foi configurado. Nada para remover."

    return 0

  fi

  if [[ ! -x "./config.sh" ]]; then

    warning "config.sh não encontrado ou não executável."

    return 0

  fi

  echo "🔧 Removendo agente Azure Pipelines..."

  # ----------------------------------------------------------
  # PAT
  # ----------------------------------------------------------
  if [[ "$AZP_AUTH" == "PAT" ]]; then

    if [[ -z "$AZP_TOKEN" ]]; then

      warning "PAT não está disponível para remover o agente."

      return 0

    fi

    until ./config.sh remove \
      --unattended \
      --auth pat \
      --token "$AZP_TOKEN"; do

      warning "Falha ao remover agente."
      warning "Tentando novamente em 5 segundos..."

      sleep 5

    done

  # ----------------------------------------------------------
  # Service Principal
  # ----------------------------------------------------------
  elif [[ "$AZP_AUTH" == "SP" ]]; then

    if [[ -z "$AZP_CLIENT_ID" ||
          -z "$AZP_CLIENT_SECRET" ||
          -z "$AZP_TENANT_ID" ]]; then

      warning "Credenciais SP não estão disponíveis para remover o agente."

      return 0

    fi

    until ./config.sh remove \
      --unattended \
      --auth SP \
      --clientid "$AZP_CLIENT_ID" \
      --clientsecret "$AZP_CLIENT_SECRET" \
      --tenantid "$AZP_TENANT_ID"; do

      warning "Falha ao remover agente."
      warning "Tentando novamente em 5 segundos..."

      sleep 5

    done

  fi

  success "Agente removido com sucesso!"
}

# ============================================================
# Shutdown
# ============================================================
handle_sigterm() {

  echo
  warning "SIGTERM recebido."
  warning "Iniciando shutdown controlado do agente..."

  exit 143
}

handle_sigint() {

  echo
  warning "SIGINT recebido."
  warning "Iniciando shutdown controlado do agente..."

  exit 130
}

# ============================================================
# Traps
# ============================================================
trap cleanup EXIT
trap handle_sigterm TERM
trap handle_sigint INT

# ============================================================
# Validação das variáveis obrigatórias
# ============================================================
required_env_vars=(
  "AZP_URL"
  "AZP_POOL"
)

for var in "${required_env_vars[@]}"; do

  if [[ -z "${!var:-}" ]]; then

    error "Variável de ambiente obrigatória ausente: $var"

    exit 1

  fi

done

# ============================================================
# Normaliza método de autenticação
# ============================================================
AZP_AUTH="$(echo "$AZP_AUTH" | tr '[:lower:]' '[:upper:]')"

case "$AZP_AUTH" in

  SP)

    success "Método de autenticação: Service Principal"

    ;;

  PAT)

    success "Método de autenticação: PAT"

    ;;

  *)

    error "AZP_AUTH inválido: $AZP_AUTH"
    error "Valores permitidos: SP ou PAT"

    exit 1

    ;;

esac

# ============================================================
# Obtém credenciais
#
# SECRETNAME definido:
#   -> AWS Secrets Manager
#
# SECRETNAME não definido:
#   -> Variáveis de ambiente
# ============================================================
if [[ -n "${SECRETNAME:-}" ]]; then

  # ==========================================================
  # AWS Secrets Manager
  # ==========================================================
  if [[ -z "${AWS_REGION:-}" ]]; then

    error "AWS_REGION é obrigatória quando SECRETNAME está definido."

    exit 1

  fi

  print_header "🔐 Buscando credenciais no AWS Secrets Manager..."

  SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETNAME" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text)

  if [[ -z "$SECRET_JSON" || "$SECRET_JSON" == "None" ]]; then

    error "Não foi possível obter o Secret: $SECRETNAME"

    exit 1

  fi

  success "Secret recuperado com sucesso."

  # ==========================================================
  # Service Principal via Secrets Manager
  # ==========================================================
  if [[ "$AZP_AUTH" == "SP" ]]; then

    AZP_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r \
      '.azuredevopsclientid // empty')

    AZP_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r \
      '.azuredevopsclientsecret // empty')

    AZP_TENANT_ID=$(echo "$SECRET_JSON" | jq -r \
      '.azuredevopstenantid // empty')

  fi

  # ==========================================================
  # PAT via Secrets Manager
  # ==========================================================
  if [[ "$AZP_AUTH" == "PAT" ]]; then

    AZP_TOKEN=$(echo "$SECRET_JSON" | jq -r \
      '.azuredevopspat // empty')

  fi

else

  # ==========================================================
  # Credenciais via Environment
  # ==========================================================
  print_header "🔐 Utilizando credenciais das variáveis de ambiente..."

  if [[ "$AZP_AUTH" == "SP" ]]; then

    AZP_CLIENT_ID="${AZP_CLIENT_ID:-}"
    AZP_CLIENT_SECRET="${AZP_CLIENT_SECRET:-}"
    AZP_TENANT_ID="${AZP_TENANT_ID:-}"

  fi

  if [[ "$AZP_AUTH" == "PAT" ]]; then

    AZP_TOKEN="${AZP_TOKEN:-}"

  fi

fi

# ============================================================
# Validação das credenciais
# ============================================================

# ------------------------------------------------------------
# Service Principal
# ------------------------------------------------------------
if [[ "$AZP_AUTH" == "SP" ]]; then

  missing=0

  if [[ -z "$AZP_CLIENT_ID" ]]; then

    error "Credencial ausente: AZP_CLIENT_ID"

    missing=1

  else

    success "AZP_CLIENT_ID encontrado."

  fi

  if [[ -z "$AZP_CLIENT_SECRET" ]]; then

    error "Credencial ausente: AZP_CLIENT_SECRET"

    missing=1

  else

    success "AZP_CLIENT_SECRET encontrado."

  fi

  if [[ -z "$AZP_TENANT_ID" ]]; then

    error "Credencial ausente: AZP_TENANT_ID"

    missing=1

  else

    success "AZP_TENANT_ID encontrado."

  fi

  if [[ "$missing" -eq 1 ]]; then

    error "Credenciais do Service Principal incompletas."

    exit 1

  fi

fi

# ------------------------------------------------------------
# PAT
# ------------------------------------------------------------
if [[ "$AZP_AUTH" == "PAT" ]]; then

  if [[ -z "$AZP_TOKEN" ]]; then

    error "Credencial ausente: AZP_TOKEN"

    exit 1

  fi

  success "AZP_TOKEN encontrado."

fi

# ============================================================
# Diretório de trabalho
# ============================================================
print_header "📁 Preparando diretório de trabalho..."

mkdir -p "$AZP_WORK"

success "Diretório de trabalho: $AZP_WORK"

# ============================================================
# Docker-in-Docker
# ============================================================
print_header "🐳 Iniciando Docker daemon..."

dockerd \
    --storage-driver=vfs \
    --data-root=/var/lib/docker \
    &

DOCKER_PID=$!

echo "⏳ Aguardando Docker ficar disponível..."

until docker info >/dev/null 2>&1; do

  # Verifica se o Docker morreu
  if ! kill -0 "$DOCKER_PID" 2>/dev/null; then

    error "Docker daemon encerrou inesperadamente."

    exit 1

  fi

  sleep 2

done

success "Docker daemon iniciado."

# ============================================================
# Configuração do agente Azure Pipelines
# ============================================================
print_header "⚙️ Configurando agente Azure Pipelines..."

if [[ "$AZP_AUTH" == "PAT" ]]; then

  ./config.sh --unattended \
    --agent "$AZP_AGENT_NAME" \
    --url "$AZP_URL" \
    --auth pat \
    --token "$AZP_TOKEN" \
    --pool "$AZP_POOL" \
    --work "$AZP_WORK" \
    --replace \
    --acceptTeeEula

elif [[ "$AZP_AUTH" == "SP" ]]; then

  ./config.sh --unattended \
    --agent "$AZP_AGENT_NAME" \
    --url "$AZP_URL" \
    --auth SP \
    --clientid "$AZP_CLIENT_ID" \
    --clientsecret "$AZP_CLIENT_SECRET" \
    --tenantid "$AZP_TENANT_ID" \
    --pool "$AZP_POOL" \
    --work "$AZP_WORK" \
    --replace \
    --acceptTeeEula

fi

AGENT_CONFIGURED=true

success "Agente Azure Pipelines configurado com sucesso."

# ============================================================
# Inicia Azure Pipelines Agent
# ============================================================
print_header "🚀 Iniciando Azure Pipelines Agent..."

chmod +x ./run.sh

# IMPORTANTE:
#
# Não utilizar:
#
#   ./run.sh --once
#
# O Deployment/KEDA precisa manter o agente disponível
# para receber múltiplos jobs.
#
# O run.sh é executado em background para que este script
# continue controlando SIGTERM e cleanup.

./run.sh &

AGENT_PID=$!

echo "Azure Pipelines Agent PID: $AGENT_PID"

# ============================================================
# Aguarda o agente
# ============================================================
wait "$AGENT_PID"

AGENT_EXIT_CODE=$?

echo
warning "Azure Pipelines Agent encerrou com código: $AGENT_EXIT_CODE"

exit "$AGENT_EXIT_CODE"