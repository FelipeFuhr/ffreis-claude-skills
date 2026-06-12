SHELL := /bin/bash

LEFTHOOK_VERSION ?= 1.7.10
LEFTHOOK_DIR     ?= $(CURDIR)/.bin
LEFTHOOK_BIN     ?= $(LEFTHOOK_DIR)/lefthook
GITLEAKS         ?= gitleaks

COMMANDS_DIR := commands
TESTS_DIR    := tests

.PHONY: help ci test test-integration lint validate secrets-scan-staged \
        lefthook-bootstrap lefthook-install lefthook-run lefthook setup \
        install-act ci-local \
        init-github

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ci: lint test ## Run all checks (lint + structural tests)

test: ## Run structural bats tests (no credentials needed)
	@command -v bats >/dev/null 2>&1 || { echo "[error] bats not installed (apt install bats)"; exit 1; }
	bats $(TESTS_DIR)/skill-structure.bats

test-integration: ## Run live-AWS integration tests (requires ffreis-platform AWS profile)
	@command -v bats >/dev/null 2>&1 || { echo "[error] bats not installed"; exit 1; }
	bats $(TESTS_DIR)/aws-billing-integration.bats

lint: ## Run markdownlint on all skill files
	@if command -v markdownlint >/dev/null 2>&1; then \
		markdownlint $(COMMANDS_DIR)/*.md; \
	else \
		echo "[warn] markdownlint not installed (npm i -g markdownlint-cli)"; \
	fi

validate: lint ## Alias: lint (kept for lefthook compat)

secrets-scan-staged: ## Scan staged diff for secrets
	@command -v $(GITLEAKS) >/dev/null 2>&1 || { echo "Missing tool: $(GITLEAKS)"; exit 1; }
	$(GITLEAKS) protect --staged --redact

lefthook-bootstrap: ## Download lefthook binary into ./.bin
	LEFTHOOK_VERSION="$(LEFTHOOK_VERSION)" BIN_DIR="$(LEFTHOOK_DIR)" bash ./scripts/bootstrap_lefthook.sh

lefthook-install: lefthook-bootstrap ## Install git hooks if missing
	@if [ -x "$(LEFTHOOK_BIN)" ] && [ -x ".git/hooks/pre-commit" ] && [ -x ".git/hooks/pre-push" ] && [ -x ".git/hooks/commit-msg" ]; then \
		echo "lefthook hooks already installed"; exit 0; \
	fi
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" install

lefthook-run: lefthook-bootstrap ## Run hooks
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run pre-commit
	@tmp_msg="$$(mktemp)"; \
	echo "chore(hooks): validate commit-msg hook" > "$$tmp_msg"; \
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run commit-msg -- "$$tmp_msg"; \
	rm -f "$$tmp_msg"

lefthook: lefthook-bootstrap lefthook-install lefthook-run ## Install hooks and run them

setup: lefthook-install ## Bootstrap hooks and verify dev tools
	@command -v actionlint >/dev/null 2>&1 || echo "WARNING: actionlint not installed. Install: https://github.com/rhysd/actionlint"
	@echo "Dev environment ready."

# ── Local CI (act-based fallback when GH Actions quota is hit) ───────────────
PLATFORM_STANDARDS_SHA ?= 3c787edb4e96ddea2e86b2add2c32139685e8db7  # v1.2.1
PLATFORM_STANDARDS_RAW ?= https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards

install-act: ## Download pinned act binary into .bin/
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/install_act.sh" \
		-o scripts/install_act.sh && chmod +x scripts/install_act.sh
	@bash ./scripts/install_act.sh

ci-local: ## Run workflows locally via act (GH Actions quota fallback). Args via ARGS=...
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/run-ci-local.sh" \
		-o scripts/run-ci-local.sh && chmod +x scripts/run-ci-local.sh
	@PATH="$(CURDIR)/.bin:$(PATH)" bash ./scripts/run-ci-local.sh $(ARGS)

# ── GitHub repo setup (run once after gh repo create) ────────────────────────
QUALITY_KIT_SCRIPTS ?= /media/ffreis/second/projects/quality-kit/scripts

init-github: ## Apply standard fleet settings to the GitHub repo (SHA-pinning, squash-only, etc.)
	@repo=$$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]||; s|\.git$$||'); \
	[ -n "$$repo" ] || { echo "No GitHub remote found" >&2; exit 1; }; \
	bash "$(QUALITY_KIT_SCRIPTS)/configure-repo-settings.sh" "$$repo"
