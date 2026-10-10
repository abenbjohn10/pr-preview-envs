# PR Preview Environments

Ephemeral, full-stack preview environments on EKS — one per pull request. Every PR gets its own namespace `pr-<N>` running the FastAPI backend, the React frontend and a private Postgres, served over HTTPS at `https://pr-<N>.preview.<domain>`. A bot comments the URL on the PR, every push redeploys, and the whole environment (namespace + images) is destroyed when the PR is merged or closed. A nightly janitor deletes anything that slipped through.

## How it works

```
PR opened / reopened / pushed
          │
          ▼
  ci.yml ─── ruff + pytest · npm build · helm lint · tf validate · shellcheck
          │
  preview.yml  (same-repo PRs only; concurrency preview-<N>, cancel-in-progress)
          │
          ├─ build ── OIDC → ECR login → buildx push
          │            preview-backend:pr-<N>-<sha>   preview-frontend:pr-<N>-<sha>
          │
          ├─ deploy ─ kubeconfig → max-previews guard (vars.MAX_PREVIEWS, default 5)
          │            scripts/preview-up.sh <N> pr-<N>-<sha>
          │              ns pr-<N> (labels preview=true, pr=<N>)
          │              helm upgrade --install preview-<N> --wait
          │                └─ postgres · backend · frontend → migrate Job (alembic + seed)
          │            smoke test: curl https://pr-<N>.preview.<domain>/api/health
          │
          └─ comment ─ sticky PR comment 🚀 URL · sha · timestamp   (or ❌ + run link)
                       GitHub environment preview-pr-<N> → URL
          │
PR merged / closed
          │
  preview-cleanup.yml
          ├─ scripts/preview-down.sh <N>   helm uninstall + delete ns pr-<N>
          ├─ ECR batch-delete-image  pr-<N>-*  (both repos)
          └─ sticky comment → 🧹 Preview destroyed

nightly  janitor.yml → scripts/janitor.sh
          delete preview=true namespaces whose PR is closed or older than MAX_AGE_DAYS
```

## Architecture

```
               *.preview.<domain>  (Route53 wildcard CNAME, Terraform)
                          │
                ingress-nginx NLB (existing, gitops-eks)
                          │  TLS: preview-wildcard-tls
      ┌───────────────────┼────────────────────┐
  ns pr-12            ns pr-13             ns preview-system
  /     → frontend    ...                  Certificate *.preview.<domain>
  /api  → backend                          (cert-manager, DNS-01, IRSA)
          → postgres                              │ reflector copies Secret
  ResourceQuota · LimitRange · NetworkPolicy      └──► every pr-[0-9]+ ns
```

- **Namespace per PR.** `pr-<N>` labelled `preview=true, pr=<N>`, Helm release `preview-<N>`. Deleting the namespace is the teardown — nothing leaks across PRs.
- **Wildcard DNS.** A single Terraform-managed `*.preview.<zone>` CNAME → ingress-nginx NLB. New previews resolve instantly; no per-PR DNS churn and no external-dns needed.
- **Wildcard TLS via reflector.** cert-manager issues one `*.preview.<domain>` cert (Let's Encrypt DNS-01 through Route53, IRSA-scoped to the zone) in `preview-system`. emberstack kubernetes-reflector copies the `preview-wildcard-tls` Secret into every `pr-[0-9]+` namespace — one ACME order total instead of one per PR, so no rate limits.
- **Postgres per PR.** Each preview runs its own `postgres:16-alpine` (emptyDir by default, optional gp2 PVC). A post-install/post-upgrade Helm hook Job runs `python -m app.migrate` (Alembic upgrade + idempotent seed); `helm --wait` doesn't return until it succeeds, so every preview is handed out with a migrated, seeded database.
- **Quotas + NetworkPolicy.** Each namespace gets a ResourceQuota (1 CPU / 1Gi requests) and LimitRange. NetworkPolicies allow ingress only from the same namespace and ingress-nginx; Postgres only accepts the backend and migrate pods.

### Security

- **Fork PRs are skipped.** `pull_request` runs from forks get no OIDC token, and every job is guarded with `head.repo.full_name == github.repository`. The workflows never use `pull_request_target`, so untrusted PR code never runs with this repo's credentials.
- **Keyless AWS auth.** GitHub OIDC → IAM role trusted only for `repo:<org>/<repo>:*`. The role can push/prune only the two preview ECR repos and `eks:DescribeCluster`.
- **Scoped Kubernetes RBAC.** The CI role is mapped by an EKS access entry to the group `preview-deployers` with **no** EKS access policy. Permissions come from the `preview-deployer` ClusterRole in `platform/rbac.yaml`, which only covers the resource kinds the chart uses — not cluster-admin.
- **cert-manager IRSA** can only change records in the one hosted zone.

### Cost

- Runs on the existing `gitops-eks` cluster and ingress NLB, so there's no per-preview AWS infrastructure: no new load balancers, no RDS, and no per-PR DNS records.
- Per-namespace ResourceQuota caps each preview. `vars.MAX_PREVIEWS` (default 5) caps how many run at once.
- Postgres uses emptyDir by default, so there are no EBS volumes to leak.
- ECR lifecycle: untagged images expire after 1 day, at most 50 `pr-` images per repo, and a PR's tags are deleted on close.
- Janitor GC runs nightly. The cluster-level budget alarm lives in gitops-eks-platform.

## Prerequisites

- Existing EKS cluster (`gitops-eks` from gitops-eks-platform) with ingress-nginx installed
- GitHub OIDC provider already in the account (created by gitops-eks-platform)
- A public Route53 hosted zone you control
- Terraform >= 1.5, AWS CLI, kubectl, helm, gh
- For the local demo: Docker + kind

## Setup

### 1. Fill in placeholders

| Placeholder | File | Value |
|---|---|---|
| `REPLACE_ME/pr-preview-envs` | `terraform/variables.tf` (`github_repo`) | Your `org/repo` |
| `REPLACE_ME_example.com` | `terraform/variables.tf` (`hosted_zone_name`) | Route53 zone, e.g. `example.com` |
| `REPLACE_ME.elb.us-east-1.amazonaws.com` | `terraform/variables.tf` (`ingress_lb_hostname`) | ingress-nginx NLB hostname (below) |
| `REPLACE_ME_ACCOUNT_ID` | `charts/preview-app/values.yaml` | AWS account ID (default registry; CI overrides it) |
| `REPLACE_ME_example.com`, `REPLACE_ME_EMAIL`, `REPLACE_ME_HOSTED_ZONE_ID` | `platform/*.yaml` | Rendered by `platform/install.sh` from env vars |

Get the NLB hostname:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 2. Provision AWS (ECR, IAM/IRSA, EKS access entry, wildcard DNS)

```bash
make tf-init
make tf-plan
make tf-apply
make tf-output
```

### 3. Install cluster add-ons (one time)

```bash
make kubeconfig
export CERT_MANAGER_ROLE_ARN=$(terraform -chdir=terraform output -raw cert_manager_role_arn)
export HOSTED_ZONE_ID=$(terraform -chdir=terraform output -raw hosted_zone_id)
export PREVIEW_DOMAIN=$(terraform -chdir=terraform output -raw preview_domain)
export ACME_EMAIL=you@example.com
make platform-install
kubectl -n preview-system get certificate preview-wildcard -w   # wait for READY=True
```

This installs cert-manager (IRSA), reflector, the `preview-deployer` RBAC, the `letsencrypt-dns01` ClusterIssuer and the wildcard Certificate.

### 4. Set GitHub repo variables

In GitHub → Settings → Secrets and variables → Actions → **Variables**:

| Variable | Value |
|---|---|
| `IAM_ROLE_ARN` | `terraform output github_actions_role_arn` |
| `ECR_REGISTRY` | `terraform output ecr_registry` (e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com`) |
| `EKS_CLUSTER_NAME` | `gitops-eks` |
| `PREVIEW_DOMAIN` | `terraform output preview_domain` (e.g. `example.com`) |
| `MAX_PREVIEWS` | optional, default `5` |
| `PREVIEW_MAX_AGE_DAYS` | optional janitor max age, default `7` |

### 5. Open a PR

The preview workflow builds, deploys and comments `https://pr-<N>.preview.<domain>`. Push again to redeploy, or close the PR to destroy it.

Manual operations:

```bash
make preview-up PR=12 TAG=pr-12-abc1234     # needs ECR_REGISTRY + PREVIEW_DOMAIN env
make preview-down PR=12
DRY_RUN=1 make janitor
```

## Local demo (kind, no AWS)

```bash
make local-up            # kind cluster + ingress-nginx + images via `kind load` + preview PR=1
open http://pr-1.localtest.me
curl http://pr-1.localtest.me/api/health
make local-up PR=2       # a second, isolated preview
make local-down
```

`*.localtest.me` resolves to 127.0.0.1. The local preview has TLS disabled (`--set ingress.tls.enabled=false`), and images are tagged `localhost/preview-*:local` and side-loaded into kind.

## Teardown

```bash
for n in $(kubectl get ns -l preview=true -o jsonpath='{.items[*].metadata.labels.pr}'); do
  make preview-down PR=$n
done
cd terraform && terraform destroy     # ECR repos are force-deleted with their images
```

Cluster add-ons (cert-manager, reflector) can be removed with `helm uninstall` in `cert-manager` / `kube-system`.

## Repo layout

```
app/backend/        FastAPI notes API + Alembic migrations + pytest
app/frontend/       Vite + React, served by nginx-unprivileged
charts/preview-app/ Helm: backend, frontend, postgres, migrate Job, ingress, quota, netpol
platform/           One-time add-ons: cert-manager, reflector, RBAC, ClusterIssuer, wildcard cert
terraform/          ECR, GH Actions role + EKS access entry, cert-manager IRSA, wildcard DNS
scripts/            preview-up.sh, preview-down.sh, janitor.sh, kind-config.yaml
.github/workflows/  ci.yml, preview.yml, preview-cleanup.yml, janitor.yml
Makefile
```
