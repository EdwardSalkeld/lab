TF_DIR := terraform
# Keep in sync with .github/workflows/format.yml.
RUFF_VERSION := 0.17.5
NIX := nix --extra-experimental-features 'nix-command flakes'

SHELL_SCRIPTS := deploy/*.sh scripts/*.sh \
	proxmox/journal-to-loki/install.sh \
	proxmox/luna/network-watchdog/install.sh \
	proxmox/luna/network-watchdog/luna-network-watchdog \
	proxmox/luna/network-watchdog/luna-network-watchdog.conf

.PHONY: help
help:
	@echo "Targets:"
	@echo "  fmt             - format Terraform, Nix, Python and Go"
	@echo "  fmt-check       - formatting checks, as CI runs them"
	@echo "  test            - shellcheck plus the script checks CI runs"
	@echo "  build HOST=...  - build a NixOS host's system closure"
	@echo "  tf-validate     - terraform init (no backend) + validate"
	@echo "  tfsec           - tfsec scan (requires tfsec)"
	@echo "  nix-check       - nix flake check"
	@echo "  check           - run fmt-check, tf-validate, tfsec, nix-check, test"

.PHONY: fmt
fmt:
	terraform fmt -recursive
	$(NIX) run --no-update-lock-file --inputs-from . nixpkgs#nixfmt-tree
	uvx --from ruff==$(RUFF_VERSION) ruff format .
	gofmt -w tools

.PHONY: fmt-check
fmt-check:
	terraform fmt -check -recursive
	$(NIX) run --no-update-lock-file --inputs-from . nixpkgs#nixfmt-tree -- --ci
	uvx --from ruff==$(RUFF_VERSION) ruff format --check .
	gofmt -d tools
	test -z "$$(gofmt -l tools)"

.PHONY: test
test:
	shellcheck $(SHELL_SCRIPTS)
	scripts/check-terraform-plan-guard.sh
	python3 -m unittest discover -s proxmox/luna/network-watchdog/tests
	python3 scripts/check-ci-deploy.py
	python3 scripts/check-host-lists.py
	python3 scripts/check-kite-backups.py
	script="$$(mktemp)" && \
		$(NIX) eval --raw .#nixosConfigurations.falcon.config.systemd.services.freshrss-sqlite-backup.script > "$$script" && \
		python3 scripts/check-freshrss-backup.py "$$script"; \
		status=$$?; rm -f "$$script"; exit $$status

.PHONY: build
build:
	@test -n "$(HOST)" || { echo 'usage: make build HOST=<host>' >&2; exit 2; }
	$(NIX) build .#nixosConfigurations.$(HOST).config.system.build.toplevel

.PHONY: tf-validate
tf-validate:
	terraform -chdir=$(TF_DIR) init -backend=false
	terraform -chdir=$(TF_DIR) validate

.PHONY: tfsec
tfsec:
	tfsec $(TF_DIR)

.PHONY: nix-check
nix-check:
	$(NIX) flake check --no-update-lock-file

.PHONY: check
check: fmt-check tf-validate tfsec nix-check test
