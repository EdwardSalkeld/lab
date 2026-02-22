TF_DIR := terraform
K8S_DIR := gitops

.PHONY: help
help:
	@echo "Targets:"
	@echo "  fmt             - terraform fmt -check -recursive"
	@echo "  tf-validate     - terraform init (no backend) + validate"
	@echo "  tfsec           - tfsec scan (requires tfsec)"
	@echo "  kubeconform     - kubeconform validation (requires kubeconform)"
	@echo "  kube-linter     - kube-linter lint (requires kube-linter)"
	@echo "  check           - run fmt, tf-validate, tfsec, kubeconform, kube-linter"

.PHONY: fmt
fmt:
	terraform fmt -check -recursive

.PHONY: tf-validate
tf-validate:
	terraform -chdir=$(TF_DIR) init -backend=false
	terraform -chdir=$(TF_DIR) validate

.PHONY: tfsec
tfsec:
	tfsec $(TF_DIR)

.PHONY: kubeconform
kubeconform:
	kubeconform -summary -ignore-missing-schemas $(K8S_DIR)/*.yaml

.PHONY: kube-linter
kube-linter:
	kube-linter lint $(K8S_DIR)

.PHONY: check
check: fmt tf-validate tfsec kubeconform kube-linter
