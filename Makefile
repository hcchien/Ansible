# Single entry point for the Ansible / Tris-Aura monorepo.
# See docs/getting-started-dev.md for first-time setup.

POSTGRES_TEST_ENV := POSTGRES_USER="$$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test

.PHONY: help setup dev dev-down test test-flutter test-app test-packages \
        test-relay test-appview test-issuer test-frontend test-rust \
        build-mcp lint analyze

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## One-time codegen (Rust FFI bridge + Drift); see setup_codegen.sh
	./setup_codegen.sh

dev: ## Start backend stack (postgres + relay + appview + issuer + frontend)
	docker compose up --build

dev-down: ## Stop the backend stack
	docker compose down

test: test-flutter test-relay test-appview test-issuer test-frontend test-rust ## Run every suite

test-flutter: test-packages test-app ## All Dart/Flutter tests

test-app: ## Flutter app tests
	cd ansible_node/app && flutter test

test-packages: ## ansible_core package tests
	cd ansible_core/domain && dart test
	cd ansible_core/store && dart test
	cd ansible_core/ap && dart test
	cd ansible_core/nostr && dart test
	cd ansible_core/did && flutter test
	cd ansible_core/vc && flutter test

test-relay: ## Relay Phoenix tests (needs local PostgreSQL)
	cd ansible_relay/phoenix && $(POSTGRES_TEST_ENV) mix ecto.create --quiet && \
		$(POSTGRES_TEST_ENV) mix ecto.migrate --quiet && \
		$(POSTGRES_TEST_ENV) mix test

test-appview: ## AppView Phoenix tests (needs local PostgreSQL)
	cd ansible_appview/phoenix && $(POSTGRES_TEST_ENV) mix ecto.create --quiet && \
		$(POSTGRES_TEST_ENV) mix ecto.migrate --quiet && \
		$(POSTGRES_TEST_ENV) mix test

test-issuer: ## Go issuer tests (Postgres-backed tests skip without ISSUER_TEST_DATABASE_URL)
	cd ansible_issuer/go && go vet ./... && go test ./...

test-frontend: ## Distribution frontend tests
	cd ansible_distribution_frontend && npm test

test-rust: ## Rust core + ansible-mcp tests
	cd ansible_rust_core && cargo test
	cd ansible_mcp && cargo test

build-mcp: ## Build the ansible-mcp local AI access binary (release)
	cd ansible_mcp && cargo build --release
	@echo "binary: ansible_mcp/target/release/ansible_mcp"

analyze: ## Static analysis (Flutter app)
	cd ansible_node/app && flutter analyze

lint: analyze ## Alias for analyze
