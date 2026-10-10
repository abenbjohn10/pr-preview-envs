CLUSTER_NAME ?= gitops-eks
REGION       ?= us-east-1
KIND_CLUSTER ?= preview-demo
LOCAL_TAG    ?= local
LOCAL_REG    := localhost
INGRESS_NGINX_KIND := https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml

.PHONY: help install test lint tf-init tf-plan tf-apply tf-output kubeconfig platform-install \
        preview-up preview-down janitor local-up local-down

help:
	@echo "make install           install backend dev deps + frontend deps"
	@echo "make test              run backend pytest"
	@echo "make lint              ruff + helm lint + shellcheck + terraform fmt"
	@echo "make tf-init           terraform init"
	@echo "make tf-plan           terraform plan"
	@echo "make tf-apply          terraform apply (ECR, IAM/IRSA, EKS access entry, wildcard DNS)"
	@echo "make tf-output         show terraform outputs (values for GitHub vars)"
	@echo "make kubeconfig        update kubeconfig for EKS cluster"
	@echo "make platform-install  one-time cluster add-ons (cert-manager, reflector, RBAC, wildcard cert)"
	@echo "make preview-up        deploy a preview  (PR=<n> TAG=<image-tag>)"
	@echo "make preview-down      destroy a preview (PR=<n>)"
	@echo "make janitor           GC stale previews (DRY_RUN=1 to only list)"
	@echo "make local-up          kind demo: cluster + ingress + preview at http://pr-<PR>.localtest.me (PR=1)"
	@echo "make local-down        delete the kind demo cluster"

install:
	pip install -r app/backend/requirements-dev.txt
	cd app/frontend && npm ci

test:
	cd app/backend && pytest -v

lint:
	cd app/backend && ruff check .
	helm lint charts/preview-app --set ingress.host=x.example.com --set prNumber=1
	shellcheck scripts/*.sh platform/*.sh
	terraform -chdir=terraform fmt -check -recursive

tf-init:
	cd terraform && terraform init

tf-plan:
	cd terraform && terraform plan

tf-apply:
	cd terraform && terraform apply

tf-output:
	cd terraform && terraform output

kubeconfig:
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(REGION)

platform-install:
	./platform/install.sh

preview-up:
	@test -n "$(PR)" || (echo "PR required (e.g. make preview-up PR=12 TAG=pr-12-abc1234)" && exit 1)
	@test -n "$(TAG)" || (echo "TAG required (e.g. make preview-up PR=12 TAG=pr-12-abc1234)" && exit 1)
	bash scripts/preview-up.sh $(PR) $(TAG)

preview-down:
	@test -n "$(PR)" || (echo "PR required (e.g. make preview-down PR=12)" && exit 1)
	bash scripts/preview-down.sh $(PR)

janitor:
	bash scripts/janitor.sh

# --- Local demo (kind) -------------------------------------------------------
# No AWS needed: images are built locally and side-loaded with `kind load`,
# TLS is disabled, and *.localtest.me resolves to 127.0.0.1.
local-up: PR ?= 1
local-up:
	@kind get clusters 2>/dev/null | grep -qx $(KIND_CLUSTER) || \
		kind create cluster --name $(KIND_CLUSTER) --config scripts/kind-config.yaml
	kubectl config use-context kind-$(KIND_CLUSTER)
	kubectl apply -f $(INGRESS_NGINX_KIND)
	kubectl -n ingress-nginx wait --for=condition=complete job --all --timeout=600s
	kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=600s
	docker build -t $(LOCAL_REG)/preview-backend:$(LOCAL_TAG) app/backend
	docker build -t $(LOCAL_REG)/preview-frontend:$(LOCAL_TAG) app/frontend
	kind load docker-image --name $(KIND_CLUSTER) \
		$(LOCAL_REG)/preview-backend:$(LOCAL_TAG) $(LOCAL_REG)/preview-frontend:$(LOCAL_TAG)
	ECR_REGISTRY=$(LOCAL_REG) PREVIEW_DOMAIN=localtest.me GIT_SHA=$(LOCAL_TAG) \
		PREVIEW_HOST=pr-$(PR).localtest.me \
		EXTRA_HELM_ARGS="--set ingress.tls.enabled=false" \
		bash scripts/preview-up.sh $(PR) $(LOCAL_TAG)
	curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://pr-$(PR).localtest.me/api/health && echo

local-down:
	kind delete cluster --name $(KIND_CLUSTER)
