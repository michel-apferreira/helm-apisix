# apisix-poc Helm Chart

Helm chart para a POC de migração do nginx-ingress para o Apache APISIX no GKE (projeto `rd-crm-stg-01`, região `us-central1`).

## Contexto

O nginx-ingress está sendo descontinuado. O Gateway API foi descartado por não suportar customizações em Lua (usadas atualmente). O **APISIX** foi escolhido como substituto por ser baseado em nginx/OpenResty e suportar simultaneamente Ingress, Gateway API e CRDs, facilitando a migração incremental.

**Objetivo da POC:** Validar a compatibilidade das configurações de Ingress do nginx-ingress com o APISIX Ingress Controller no cluster CRM (maior complexidade de Ingress).

## Arquitetura

```
Consumers → Cloud Armor → Global LB → Standalone NEG
                                            ↓
                              apisix-ingress-controller
                              (observa Ingress/HTTPRoute)
                                            ↓
                               APISIX Admin API (porta 9180)
                                            ↓
                              etcd cluster (3 nós, 1 por zona)
                                            ↓
                    APISIX data plane (réplicas por zona a/c/f)
                                            ↓
                               product-api (serviços upstream)
```

O Keycloak fornece autenticação OAuth2/OIDC via plugin `openid-connect` do APISIX.

## Componentes

| Componente | Versão | Descrição |
|---|---|---|
| Apache APISIX | 3.14.1 | Data + Control plane (modo `traditional`) |
| APISIX Ingress Controller | 2.0.1 | Converte Ingress → rotas APISIX |
| etcd | 3.6.0 | Backend de configuração do APISIX |
| Keycloak | 26.5.4 | IdP para autenticação (plugin openid-connect) |

## Pré-requisitos

- Helm >= 3.14
- kubectl configurado para o cluster alvo
- StorageClass `premium-rwo` disponível no cluster (Regional SSD no GKE)
- Repositório Helm do APISIX adicionado:
  ```bash
  helm repo add apisix https://apache.github.io/apisix-helm-chart
  helm repo update
  ```

## Instalação

### Atualizar dependências
```bash
helm dependency update .
```

### Deploy em staging (rd-crm-stg-01)
```bash
helm install apisix-gateway . \
  --namespace ingress-apisix \
  --create-namespace \
  --values values.yaml \
  --values values-staging.yaml \
  --set "apisix.externalEtcd.host[0]=http://apisix-gateway-etcd.ingress-apisix.svc.cluster.local:2379" \
  --set "apisix.ingress-controller.gatewayProxy.provider.controlPlane.service.name=apisix-gateway-apisix-admin" \
  --set "apisix.apisix.admin.credentials.admin=<ADMIN_TOKEN_SEGURO>" \
  --set "apisix.ingress-controller.gatewayProxy.provider.controlPlane.auth.adminKey.value=<ADMIN_TOKEN_SEGURO>" \
  --set "keycloak.auth.adminPassword=<SENHA_SEGURA>" \
  --set "keycloak.database.host=<IP_CLOUD_SQL>"
```

### Deploy local (minikube/kind)
```bash
helm install apisix-dev . \
  --namespace ingress-apisix \
  --create-namespace \
  --values values.yaml \
  --values values-local.yaml \
  --set "apisix.externalEtcd.host[0]=http://apisix-dev-etcd.ingress-apisix.svc.cluster.local:2379" \
  --set "apisix.ingress-controller.gatewayProxy.provider.controlPlane.service.name=apisix-dev-apisix-admin"
```

### Usando o script de deploy
```bash
# Staging
./deploy.sh apisix-gateway ingress-apisix staging

# Local
./deploy.sh apisix-dev ingress-apisix local

# Dry-run
./deploy.sh apisix-gateway ingress-apisix staging --dry-run
```

## Validação pós-deploy

```bash
# Verificar pods
kubectl get pods -n ingress-apisix

# Verificar IngressClass criada
kubectl get ingressclass

# Testar Admin API
kubectl port-forward -n ingress-apisix svc/apisix-gateway-apisix-admin 9180:9180
curl http://localhost:9180/apisix/admin/routes -H "X-API-KEY: <ADMIN_TOKEN>"

# Verificar etcd cluster
kubectl exec -n ingress-apisix apisix-gateway-etcd-0 -- \
  etcdctl endpoint health \
    --endpoints=http://apisix-gateway-etcd-0.apisix-gateway-etcd:2379,\
http://apisix-gateway-etcd-1.apisix-gateway-etcd:2379,\
http://apisix-gateway-etcd-2.apisix-gateway-etcd:2379
```

## Migração de Ingress (nginx → APISIX)

Para testar a migração, adicione a annotation `ingressClassName: apisix` em um Ingress existente:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: meu-servico
  namespace: meu-namespace
  # annotations nginx existentes são suportadas pelo APISIX Ingress Controller
  # nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: apisix  # ← mudar de 'nginx' para 'apisix'
  rules:
    - host: meu-servico.exemplo.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: meu-servico
                port:
                  number: 80
```

## Configuração do Keycloak (plugin openid-connect)

Após o deploy, configure o plugin no APISIX:

```bash
curl http://localhost:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: <ADMIN_TOKEN>" \
  -X PUT \
  -d '{
    "uri": "/api/*",
    "plugins": {
      "openid-connect": {
        "client_id": "apisix",
        "client_secret": "SEU_CLIENT_SECRET",
        "discovery": "http://apisix-gateway-keycloak.ingress-apisix.svc.cluster.local:8080/realms/master/.well-known/openid-configuration",
        "redirect_uri": "https://seu-dominio.com/callback",
        "scope": "openid",
        "bearer_only": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"product-api.produto.svc.cluster.local:8080": 1}
    }
  }'
```

## Estrutura do Chart

```
helm-apisix/
├── Chart.yaml                    # Definição do chart + dependência apisix
├── Chart.lock                    # Lock de versões das dependências
├── values.yaml                   # Valores default completos
├── values-staging.yaml           # Overrides para rd-crm-stg-01
├── values-local.yaml             # Overrides para desenvolvimento local
├── deploy.sh                     # Script de deploy automatizado
├── templates/
│   ├── _helpers.tpl              # Funções auxiliares
│   ├── NOTES.txt                 # Instruções pós-instalação
│   ├── etcd-service.yaml         # Servico headless do etcd
│   ├── etcd-statefulset.yaml     # StatefulSet do etcd (3 nós, anti-afinidade por zona)
│   ├── keycloak-service.yaml     # Services do Keycloak (ClusterIP + headless)
│   ├── keycloak-statefulset.yaml # StatefulSet do Keycloak
│   ├── keycloak-secret.yaml      # Secrets de credenciais do Keycloak
│   ├── keycloak-postgres.yaml    # PostgreSQL local (apenas para POC/dev)
│   └── keycloak-init-configmap.yaml  # ConfigMap de configuração do DB
└── charts/
    └── apisix-2.12.6.tgz         # Subchart apache/apisix (gerenciado pelo helm dep)
```

## Próximos Passos (Pós-POC)

1. Migrar para modo `decoupled` (control_plane + data_plane separados) para escala horizontal independente
2. Habilitar TLS no APISIX (`apisix.apisix.ssl.enabled=true`) com cert-manager
3. Habilitar ServiceMonitor (`apisix.metrics.serviceMonitor.enabled=true`) para Prometheus
4. Substituir PostgreSQL local por Cloud SQL gerenciado
5. Configurar Cloud Armor policies via APISIX (plugin `ip-restriction`)
