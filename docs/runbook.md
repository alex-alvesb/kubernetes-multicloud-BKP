# Runbook — Operação dos Clusters (AWS EKS + Azure AKS)

## AWS EKS — Início do dia

1. Checar IP público atual: `curl -s https://checkip.amazonaws.com`
2. Atualizar `aws-eks/terraform/terraform.tfvars` com o IP (se mudou)
3. Atualizar `aws-eks/k8s/monitoring/ingress-grafana.yaml` com o IP, **commitar e dar push**
   (esse arquivo é gerenciado via GitOps — editar só localmente não tem efeito)
4. `cd aws-eks/terraform && terraform apply` — **dar tempo suficiente** (cluster EKS leva
   10-15 min; nunca rodar com timeout curto, ver "Lições aprendidas" abaixo)
5. Reconectar kubectl:
   ```bash
   aws eks update-kubeconfig --name kubernetes-multicloud-eks --region us-east-1
   aws eks update-kubeconfig --name kubernetes-multicloud-eks --region us-east-1 \
     --profile eks-tester --alias eks-tester --user-alias eks-tester
   kubectl config use-context arn:aws:eks:us-east-1:679346886253:cluster/kubernetes-multicloud-eks
   ```
6. Instalar ArgoCD (único bootstrap manual restante):
   ```bash
   helm install argocd argo/argo-cd -n argocd --create-namespace
   ```
7. Subir tudo o resto via GitOps:
   ```bash
   kubectl apply -f shared/argocd/root-app.yaml
   kubectl apply -f aws-eks/argocd/aws-load-balancer-controller-app.yaml
   kubectl apply -f aws-eks/argocd/cluster-autoscaler-app.yaml
   kubectl apply -f aws-eks/argocd/metrics-server-app.yaml
   kubectl apply -f aws-eks/argocd/aws-monitoring-app.yaml
   kubectl apply -f aws-eks/argocd/sample-app-app.yaml
   ```
8. Rebuildar a imagem da sample-app (o ECR é destruído todo dia, a tag antiga não existe mais):
   vai em Actions → **Build and Deploy Sample App** → **Run workflow**

## AWS EKS — Fim do dia

**Importante: nunca rodar `terraform destroy` direto.** Primeiro:

1. Deletar a Application do Ingress via ArgoCD (dá tempo do ALB Controller desprovisionar
   o Load Balancer e os Security Groups antes da VPC ser destruída):
   ```bash
   kubectl delete application aws-monitoring-ingress -n argocd
   ```
2. Aguardar ~30-60s e confirmar que não sobrou nada:
   ```bash
   aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='<vpc_id>']"
   ```
3. Só então:
   ```bash
   cd aws-eks/terraform
   terraform destroy   # sem pressa, sem timeout curto
   ```

## Azure AKS — Início do dia

1. Checar IP público atual
2. Atualizar `azure-aks/terraform/terraform.tfvars` com o IP (se mudou)
3. Atualizar `azure-aks/k8s/monitoring/ingress-grafana.yaml` com o IP, **commitar e dar push**
4. Confirmar login do Azure CLI: `az account show`. Se expirou, usar `az login` **sem**
   `--use-device-code` (ver "Lições aprendidas" — o device code costuma ser bloqueado)
5. `cd azure-aks/terraform && terraform apply` — geralmente mais rápido que o EKS (~5-10 min),
   mas ainda assim sem timeout curto
6. Reconectar kubectl:
   ```bash
   az aks get-credentials --resource-group rg-kubernetes-multicloud \
     --name aks-kubernetes-multicloud --overwrite-existing
   ```
7. Instalar ArgoCD (bootstrap manual):
   ```bash
   helm install argocd argo/argo-cd -n argocd --create-namespace
   ```
8. Subir tudo o resto via GitOps:
   ```bash
   kubectl apply -f shared/argocd/root-app.yaml
   kubectl apply -f azure-aks/argocd/azure-monitoring-app.yaml
   ```
   (metrics-server **não** precisa ser instalado — já vem nativo no AKS)

## Azure AKS — Fim do dia

Mais simples que a AWS: o Azure limpa automaticamente o Load Balancer/IP público do
Ingress junto com o cluster (fica num Resource Group interno `MC_*` que o AKS gerencia
sozinho). Não precisa apagar o Ingress manualmente antes:
```bash
cd azure-aks/terraform
terraform destroy   # sem pressa, sem timeout curto
```

## Lições aprendidas — AWS

- **ALB/ENI/Security Group órfãos no destroy**: o AWS Load Balancer Controller cria recursos
  fora do controle do Terraform. Se o cluster morre antes dele limpar, a VPC/subnets ficam
  presas. Sempre apagar o Ingress antes do destroy.
- **ArgoCD não faz cascade delete por padrão**: sem o finalizer
  `resources-finalizer.argocd.argoproj.io` na Application, deletar a Application não apaga
  os recursos que ela gerenciava. Todas as nossas Applications já têm esse finalizer.
- **CRDs do kube-prometheus-stack são grandes demais pro client-side apply**: excedem o limite
  de 256KB da annotation `last-applied-configuration`. Solução: `ServerSideApply=true` no
  `syncOptions` da Application.
- **Prometheus Operator não detecta CRDs instaladas depois dele iniciar**: se isso acontecer,
  `kubectl rollout restart deployment kube-prometheus-stack-operator -n monitoring`.
- **`sub` claim do OIDC do GitHub mudou de formato**: agora inclui IDs imutáveis
  (`repo:owner@id/repo@id:ref:...`), não só nomes.
- **ECR não deixa apagar repositório com imagens**: `force_delete = true` é necessário no
  `aws_ecr_repository`, já que esse repo é recriado todo dia.
- **Timeouts curtos em operações de cluster são perigosos**: um `apply`/`destroy` interrompido
  no meio pode deixar recursos reais na nuvem que o Terraform não sabe mais que existem
  (aconteceu com um cluster EKS órfão). Sempre dar tempo generoso (15-20 min).
- **IP doméstico muda com frequência**: tanto o `terraform.tfvars` quanto o
  `ingress-grafana.yaml` (via commit, por causa do GitOps) precisam ser atualizados no
  início do dia.

## Lições aprendidas — Azure

- **Resource Providers precisam ser registrados manualmente** na primeira vez que a
  subscription usa um serviço novo (`Microsoft.Network`, `Microsoft.ContainerService`, etc):
  `az provider register --namespace <nome>`.
- **`azurerm` provider v5.x exige o bloco `node_provisioning_profile`** no
  `azurerm_kubernetes_cluster`, mesmo usando node pools tradicionais — declarar
  `mode = "Manual"`.
- **Subscriptions trial têm quota zero pra várias famílias de VM** (ex: série `B` antiga).
  Conferir com `az vm list-usage --location <região>` antes de escolher o `vm_size`.
- **`az login --use-device-code` pode ser bloqueado pela política "Security Defaults"**
  do tenant (`AADSTS530035`) — esse fluxo tem sido alvo de phishing e vem sendo restringido.
  Usar `az login` padrão (redirect via `localhost`) resolve.
- **`web_app_routing` exige `dns_zone_ids`** (lista) mesmo sem domínio próprio — usar `[]`.
- **Restrição de IP no Ingress usa outra anotação**: `nginx.ingress.kubernetes.io/whitelist-source-range`
  (não `inbound-cidrs`, que é específico do ALB Controller da AWS).
- **`shared/argocd/` deve conter só o que é realmente cloud-agnostic**: componentes que
  referenciam IAM Role da AWS (Cluster Autoscaler, ALB Controller) ou que são redundantes
  numa cloud (metrics-server no AKS) devem morar na pasta específica da cloud
  (`aws-eks/argocd/`), não em `shared/argocd/` — senão o `root-app` de uma cloud tenta
  instalar componente da outra.

## Lições aprendidas — CI/CD (GitHub Actions, geral — não específico de cloud)

- **CRLF quebra o parser do GitHub Actions**: se o arquivo `.yml` for salvo com quebra de
  linha estilo Windows, o workflow falha silenciosamente ("0 jobs", nome do workflow cai
  pro caminho do arquivo). Resolvido com `.gitattributes` (`eol=lf`) forçando LF sempre.
- **`run:` de uma linha só com `:` dentro do valor quebra o YAML**: um `:` seguido de espaço
  (`"s|image: .*|image: ..."`) é interpretado como início de um mapeamento YAML se não
  estiver dentro de um bloco `|`. Sempre que o comando shell tiver `: ` no meio, usar bloco
  multi-linha (`run: |`), nunca linha única.
- **`actions/checkout` deixa HEAD desanexado**: um `git push` sem destino explícito falha
  de forma ambígua. Usar sempre `git push origin HEAD:main`.
- **Ordem importa: commit antes do `pull --rebase`**: se o arquivo já foi alterado por um
  step anterior (ex: `sed`) e ainda não foi commitado, `git pull --rebase` falha
  (`cannot pull with rebase: you have unstaged changes`). Sempre `add` + `commit` primeiro,
  `pull --rebase` depois, `push` por último.
- **Um job só, sequencial, pra duas clouds é frágil**: se uma infraestrutura estiver fora do
  ar (ex: AWS destruída), isso não deveria impedir o deploy pra outra cloud que está de pé.
  Jobs paralelos independentes (`deploy-aws`, `deploy-azure`) resolvem isso.

## Lições aprendidas — GitOps (ArgoCD) e HPA

- **`directory.recurse: true` num path "pai" pode varrer pastas de outras Applications sem
  querer**: a `aws-monitoring-ingress`/`azure-monitoring-ingress` apontavam pra
  `aws-eks/k8s`/`azure-aks/k8s` (a pasta toda) em vez de `aws-eks/k8s/monitoring` — isso
  fez elas "adotarem" também o `sample-app/`, brigando com a Application `sample-app` pelo
  mesmo Deployment/Service/HPA (aparece como `SharedResourceWarning` nas conditions da
  Application). Sintoma: recursos oscilando entre estados sem motivo aparente. Sempre
  escopar o `path` na pasta mais específica possível, nunca num diretório pai compartilhado.
- **HPA e `selfHeal` do ArgoCD brigam pelo campo `replicas`**: se o manifest do Deployment
  declara `replicas: N` e tem um HPA ativo, o ArgoCD (com `selfHeal: true`) tenta reverter
  pro valor do Git toda vez que o HPA muda o valor real — um looping de scale up/down.
  Resolvido com `ignoreDifferences` na Application, apontando pro campo `/spec/replicas`
  do `Deployment`, deixando o HPA ser o único dono desse campo.
- **Teste de carga real (HPA)**: com CPU acima do limiar (50% do request), o HPA escalou de
  1 para 2 réplicas em ~22s (pod `Running` já servindo tráfego). Após a carga cessar, o
  scale-down aconteceu depois da janela de estabilização padrão (~5 min) — comportamento
  esperado, evita "flapping" por uma flutuação passageira de CPU.