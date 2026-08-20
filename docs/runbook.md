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

## GCP GKE — Início do dia

1. Checar IP público atual
2. Atualizar `gcp-gke/terraform/terraform.tfvars` com o IP (se mudou)
3. Confirmar login: `gcloud auth list`. Se expirou, `gcloud auth login` (mesmo truque do
   Azure — deixa tentar abrir navegador, copia o link manualmente se falhar)
4. `cd gcp-gke/terraform && terraform apply` — sem timeout curto
5. Reconectar kubectl: `gcloud container clusters get-credentials gke-kubernetes-multicloud
   --location=us-central1-a --project=kubernetes-multicloud`
6. Reaplicar `shared/k8s/` (namespaces, RBAC, network policies) — **o cluster GKE tende a
   ser recriado por inteiro a cada apply** (ver lições abaixo), então isso quase sempre é
   necessário de novo, diferente da AWS/Azure onde só recriamos o cluster no dia seguinte
7. Reinstalar `kube-prometheus-stack` via Helm com o mesmo values file
8. Aplicar `gcp-gke/k8s/monitoring/ingress-grafana.yaml` e rodar
   `kubectl annotate service kube-prometheus-stack-grafana -n monitoring
   'cloud.google.com/neg={"ingress": true}' --overwrite` (necessário toda vez que a
   instalação do Helm é refeita)

## GCP GKE — Fim do dia

Sem Ingress complexo pra limpar antes (Load Balancer do GCP se desprovisiona junto com o
Ingress/cluster sem o mesmo drama do ALB da AWS). Só:
```bash
cd gcp-gke/terraform
terraform destroy   # sem pressa, sem timeout curto
```

## Lições aprendidas — GCP

- **Billing precisa ser vinculado manualmente ao Project** antes de criar qualquer coisa
  (`gcloud billing projects describe <project>` mostra `billingEnabled: false` se faltar).
- **`gcloud auth login` autentica o CLI; `gcloud auth application-default login` autentica
  o Terraform** — são credenciais separadas, os dois logins são necessários.
- **Comandos `gcloud`/`gsutil` instalados via script não entram no `PATH` de sessões novas**
  automaticamente — precisa adicionar ao `.bashrc` manualmente
  (`export PATH="$HOME/google-cloud-sdk/bin:$PATH"`).
- **Quota de disco (`SSD_TOTAL_GB`) e de endereços IP (`IN_USE_ADDRESSES`) são bem
  limitadas em projetos trial** (250GB e 4 endereços, nesse caso). Reduzir `disk_size_gb`
  dos nodes e conferir `gcloud compute regions describe <região>` antes de escalar.
- **`location` regional (`us-central1`) faz o GKE replicar o node pool em várias zonas
  automaticamente** — `node_count = 2` numa região pode virar 4+ instâncias reais. Usar uma
  zona específica (`us-central1-a`) pra ter controle exato da contagem de nodes, além de
  ser um cluster "zonal" mais barato que um "regional".
- **`deletion_protection` vem ligado por padrão em clusters GKE recentes** — sem
  `deletion_protection = false` explícito, o `terraform destroy` diário simplesmente falha.
- **VMs pequenas (`e2-medium`, 2 vCPU) reservam uma fatia desproporcional de CPU pra
  overhead de sistema** (só ~940m de 2000m ficam alocáveis) — com Calico rodando (NetworkPolicy),
  sobra pouquíssimo espaço pro workload real. Aumentar o *tamanho* da VM (`e2-standard-4`)
  ajuda mais que aumentar a *quantidade* de nodes pequenos, já que cada node novo carrega
  seu próprio overhead de sistema/Calico.
- **Mudar `node_count` ou `machine_type` no node pool tende a recriar o cluster inteiro**,
  não só o node pool — isso apaga namespaces, RBAC e releases do Helm. Diferente do
  EKS/AKS, onde só o node pool em si é afetado. Planeje o `terraform apply` do dia
  assumindo que pode ser preciso reaplicar tudo de novo, não só reconectar o `kubectl`.
- **`gke-gcloud-auth-plugin` precisa ser instalado à parte** (`gcloud components install
  gke-gcloud-auth-plugin`) — sem ele, o `kubectl` não consegue autenticar no GKE.
- **O Ingress nativo do GKE (`kubernetes.io/ingress.class: gce`) exige Service tipo
  `NodePort`/`LoadBalancer`, ou a anotação de NEG** (`cloud.google.com/neg: '{"ingress":
  true}'`) pra funcionar com `ClusterIP` — sem isso, o Ingress fica preso em
  "Translation failed". O Load Balancer do GCP também demora mais pra provisionar
  (5-10 min) que o ALB da AWS ou o NGINX do Azure.
- **Não existe (de forma simples) uma anotação de allowlist de IP no Ingress nativo do
  GKE** — precisaria de Cloud Armor (mais complexo). Trade-off aceito: Grafana fica
  protegido só pela própria autenticação, sem restrição de IP na borda, diferente de AWS
  e Azure.

## Lições aprendidas — CI/CD multicloud (as 3 clouds juntas)

- **O `client-id` da Managed Identity do Azure muda a cada `terraform destroy`/`apply`**
  (é um GUID novo do recurso recriado) — diferente da AWS (ARN fixo, por nome) e do GCP
  (WIF provider com nome fixo, sobrevive à recriação). Antes de rodar o workflow depois de
  recriar o Azure, atualizar o `client-id` no `.github/workflows/build-sample-app.yml` com
  `az identity show --resource-group rg-kubernetes-multicloud --name id-github-actions
  --query clientId -o tsv`, commitar e dar push.
- **Workload Identity Pool/Provider do GCP são "soft-deleted"** — ficam reservados por até
  30 dias após `terraform destroy`, e recriar com o mesmo nome dá erro 409 "already exists".
  Resolvido com `gcloud iam workload-identity-pools undelete` (e o mesmo comando com
  `providers undelete` pro provider), seguido de `terraform import` dos dois recursos de
  volta pro state antes de reaplicar.
- **Jobs paralelos commitando no mesmo repositório colidem (`fetch first` rejected)**:
  quando `deploy-aws`/`deploy-azure`/`deploy-gcp` rodam ao mesmo tempo, cada um faz
  `git pull --rebase` + `git push`, e é comum um deles pegar o repositório "desatualizado"
  bem no instante entre o pull e o push do outro job. Resolvido com um loop de retry
  (`git pull --rebase && git push || sleep && repete`, até 5 tentativas) em vez de uma
  tentativa única.