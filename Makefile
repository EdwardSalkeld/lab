TF_DIR := terraform

.PHONY: help
help:
	@echo "Targets:"
	@echo "  fmt             - terraform fmt -check -recursive"
	@echo "  tf-validate     - terraform init (no backend) + validate"
	@echo "  tfsec           - tfsec scan (requires tfsec)"
	@echo "  nix-check       - nix flake check"
	@echo "  check           - run fmt, tf-validate, tfsec, nix-check"

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

.PHONY: nix-check
nix-check:
	nix flake check --no-update-lock-file

.PHONY: check
check: fmt tf-validate tfsec nix-check
