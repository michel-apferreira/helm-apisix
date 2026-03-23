#!/usr/bin/env bash
# deploy.sh - Script de deploy do APISIX POC
#
# Uso:
#   ./deploy.sh [RELEASE_NAME] [NAMESPACE] [ENV]
#
# Exemplos:
#   ./deploy.sh apisix-gateway ingress-apisix staging   # staging com valores default
#   ./deploy.sh apisix-dev ingress-apisix local         # desenvolvimento local
#   ./deploy.sh apisix-gateway ingress-apisix staging --dry-run  # apenas visualizar

set -euo pipefail

RELEASE_NAME="${1:-apisix-gateway}"
NAMESPACE="${2:-ingress-apisix}"
ENV="${3:-local}"
EXTRA_ARGS="${4:-}"

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==================================================================="
echo " APISIX POC - Deploy"
echo " Release:   ${RELEASE_NAME}"
echo " Namespace: ${NAMESPACE}"
echo " Ambiente:  ${ENV}"
echo "==================================================================="

# Atualizar dependencias do chart
echo ""
echo "► Atualizando dependencias do chart..."
helm dependency update "${CHART_DIR}"

# Definir arquivo de values por ambiente
VALUES_FILE="${CHART_DIR}/values.yaml"
ENV_VALUES_FILE="${CHART_DIR}/values-${ENV}.yaml"

if [ ! -f "${ENV_VALUES_FILE}" ]; then
  echo "AVISO: Arquivo de values para ambiente '${ENV}' nao encontrado: ${ENV_VALUES_FILE}"
  echo "       Usando apenas o values.yaml principal."
  ENV_VALUES_FILE=""
fi

# Criar namespace se nao existir
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || \
  kubectl create namespace "${NAMESPACE}"

# Montar comando de instalacao/upgrade
HELM_CMD=(
  helm upgrade --install "${RELEASE_NAME}"
  "${CHART_DIR}"
  --namespace "${NAMESPACE}"
  --values "${VALUES_FILE}"
  --timeout 10m
  --wait
)

if [ -n "${ENV_VALUES_FILE}" ]; then
  HELM_CMD+=(--values "${ENV_VALUES_FILE}")
fi

# Sets obrigatorios: substituir placeholders no values.yaml
# O externalEtcd.host precisa do Release.Name correto
HELM_CMD+=(--set "apisix.externalEtcd.host[0]=http://${RELEASE_NAME}-etcd.${NAMESPACE}.svc.cluster.local:2379")
# O GatewayProxy precisa apontar para o servico admin do APISIX
HELM_CMD+=(--set "apisix.ingress-controller.gatewayProxy.provider.controlPlane.service.name=${RELEASE_NAME}-apisix-admin")

# Args extras (ex: --dry-run, --debug)
if [ -n "${EXTRA_ARGS}" ]; then
  HELM_CMD+=("${EXTRA_ARGS}")
fi

echo ""
echo "► Executando: ${HELM_CMD[*]}"
echo ""

"${HELM_CMD[@]}"

echo ""
echo "==================================================================="
echo " Deploy concluido! Verifique o status dos pods:"
echo ""
echo "   kubectl get pods -n ${NAMESPACE}"
echo "   kubectl get ingressclass"
echo "==================================================================="
