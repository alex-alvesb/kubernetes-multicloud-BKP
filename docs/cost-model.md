# Modelo de Custo — AWS EKS Lab

## Filosofia

Este é um laboratório de estudos, não um ambiente de produção real. A estratégia de custo
não é "usar os recursos mais baratos possíveis", e sim: **simular decisões de produção,
mas escolher o lado mais barato em cada trade-off, documentando conscientemente o que se
perde em cada escolha.** O maior fator de economia não é nenhuma configuração — é o hábito
de rodar `terraform destroy` no fim do dia.

## Decisões de custo x produção real

| Decisão | O que fizemos | O que produção real faria | Economia |
|---|---|---|---|
| NAT Gateway | 1 único, compartilhado | 1 por AZ (alta disponibilidade) | ~$33/mês por NAT a menos (validado via Infracost) |
| Nodes EKS | Managed Node Group Spot | On-Demand ou Reserved | Spot costuma custar 60-90% menos que On-Demand |
| Availability Zones | 2 AZs | 3 AZs | Menos NAT/subnets pra manter |
| Versão do EKS | Sempre dentro do "standard support" | Idem, mas monitorado | Evita ~$0.60/hora extra de "Extended Support" |
| Retenção do Prometheus | 6 horas, sem storage persistente | 15-30 dias, com EBS | Sem custo de EBS/PV, cluster é efêmero mesmo |
| Grafana/Ingress | HTTP simples, restrito por IP | HTTPS com domínio próprio + ACM | Sem custo de Route53/domínio |
| ECR | Lifecycle policy (10 imagens) | Política de retenção maior | Sem crescimento de custo de storage ao longo do tempo |

## Estimativa de custo por hora rodando

| Recurso | Custo aproximado |
|---|---|
| EKS control plane | $0.10/hora |
| 2x EC2 t3.medium (Spot) | ~$0.02–0.04/hora |
| NAT Gateway | $0.045/hora + $0.045/GB processado |
| ALB (Grafana) | $0.0225/hora + LCU |
| **Total aproximado** | **~$0.20–0.30/hora** |

Isso dá algo como **$2-3 por um dia inteiro (8h) de estudo** — e $0 quando está destruído.

## Práticas de FinOps aplicadas

- **Tagging consistente** (`Project`, `Environment`, `ManagedBy`) em todo recurso, via `default_tags`
- **AWS Budget** com alerta em 80% do gasto real e 100% do gasto projetado ($10/mês)
- **Infracost** comentando o impacto de custo de cada Pull Request antes do merge
- **Lifecycle policy no ECR** evitando acúmulo indefinido de imagens
- **Disciplina de destroy diário** — a alavanca mais importante de todas