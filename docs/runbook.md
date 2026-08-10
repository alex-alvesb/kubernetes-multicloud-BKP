# Runbook — Operação do Cluster AWS EKS

## Início do dia

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
   kubectl apply -f aws-eks/argocd/aws-monitoring-app.yaml
   kubectl apply -f aws-eks/argocd/sample-app-app.yaml
   ```
8. Rebuildar a imagem da sample-app (o ECR é destruído todo dia, a tag antiga não existe mais):
   vai em Actions → **Build and Deploy Sample App** → **Run workflow**

## Fim do dia

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

## Lições aprendidas (bugs reais que já pegamos)

- **ALB/ENI/Security Group órfãos no destroy**: o AWS Load Balancer Controller cria recursos
  fora do controle do Terraform. Se o cluster morre antes dele limpar, a VPC/subnets ficam
  presas. Sempre apagar o Ingress antes do destroy (ver "Fim do dia").
- **ArgoCD não faz cascade delete por padrão**: sem o finalizer
  `resources-finalizer.argocd.argoproj.io` na Application, deletar a Application não apaga
  os recursos que ela gerenciava — eles ficam órfãos no cluster. Todas as nossas Applications
  já têm esse finalizer.
- **CRDs do kube-prometheus-stack são grandes demais pro client-side apply**: excedem o limite
  de 256KB da annotation `last-applied-configuration`. Solução: `ServerSideApply=true` no
  `syncOptions` da Application.
- **Prometheus Operator não detecta CRDs instaladas depois dele iniciar**: se isso acontecer,
  `kubectl rollout restart deployment kube-prometheus-stack-operator -n monitoring`.
- **`sub` claim do OIDC do GitHub mudou de formato**: agora inclui IDs imutáveis
  (`repo:owner@id/repo@id:ref:...`), não só nomes. Sempre conferir o claim real (decodificando
  o JWT) em vez de assumir o formato documentado antigamente.
- **ECR não deixa apagar repositório com imagens**: como esse repo é recriado todo dia,
  `force_delete = true` é necessário no `aws_ecr_repository`.
- **Timeouts curtos em operações de cluster são perigosos**: um `apply`/`destroy` interrompido
  no meio pode deixar recursos reais na AWS que o Terraform não sabe mais que existem
  (aconteceu com um cluster EKS órfão). Sempre dar tempo generoso (15-20 min) pra essas operações.
- **IP doméstico muda com frequência**: tanto o `terraform.tfvars` quanto o
  `ingress-grafana.yaml` (esse via commit, por causa do GitOps) precisam ser atualizados
  no início do dia.