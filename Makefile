# Hermis Platform Makefile
# Simplifies development workflow and code quality checks

# Colors for output
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
NC = \033[0m # No Color

.PHONY: help install build test clean lint format lint-security lint-all

help: ## Show this help message
	@echo "$(GREEN)Hermis Platform Development Commands$(NC)"
	@echo "===================================="
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install: ## Install dependencies
	@echo "$(GREEN)Installing dependencies...$(NC)"
	forge install

build: ## Build contracts
	@echo "$(GREEN)Building contracts...$(NC)"
	forge build

test: ## Run tests
	@echo "$(GREEN)Running tests...$(NC)"
	forge test -vv

test-coverage: ## Run tests with coverage
	@echo "$(GREEN)Running tests with coverage...$(NC)"
	forge coverage

lint: ## Lint source contracts with Solhint (excludes tests)
	@echo "$(GREEN)Linting contracts...$(NC)"
	@command -v solhint >/dev/null 2>&1 || { echo "$(YELLOW)Installing solhint...$(NC)"; npm install -g solhint; }
	solhint 'src/**/*.sol'

lint-tests: ## Lint test files with Solhint
	@echo "$(GREEN)Linting test files...$(NC)"
	@command -v solhint >/dev/null 2>&1 || { echo "$(YELLOW)Installing solhint...$(NC)"; npm install -g solhint; }
	solhint 'test/**/*.sol'

lint-full: ## Lint all contracts including tests
	@echo "$(GREEN)Linting all contracts...$(NC)"
	@command -v solhint >/dev/null 2>&1 || { echo "$(YELLOW)Installing solhint...$(NC)"; npm install -g solhint; }
	solhint 'src/**/*.sol' 'test/**/*.sol'

lint-security: ## Run security analysis with Slither
	@echo "$(GREEN)Running security analysis...$(NC)"
	@command -v slither >/dev/null 2>&1 || { echo "$(YELLOW)Installing slither...$(NC)"; pip3 install slither-analyzer; }
	slither . --filter-paths lib/

format: ## Format contracts with Forge and Prettier
	@echo "$(GREEN)Formatting contracts...$(NC)"
	forge fmt
	@command -v prettier >/dev/null 2>&1 || { echo "$(YELLOW)Installing prettier...$(NC)"; npm install -g prettier prettier-plugin-solidity; }
	prettier --write 'src/**/*.sol' 'test/**/*.sol'

format-check: ## Check if contracts are formatted
	@echo "$(GREEN)Checking contract formatting...$(NC)"
	forge fmt --check

lint-all: format-check lint lint-security ## Run all linting tools (source files only)
	@echo "$(GREEN)All linting checks completed!$(NC)"

lint-all-full: format-check lint-full lint-security ## Run all linting tools including tests
	@echo "$(GREEN)All linting checks (including tests) completed!$(NC)"

clean: ## Clean build artifacts
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	forge clean
	rm -rf cache/
	rm -rf out/

gas-report: ## Generate gas usage report
	@echo "$(GREEN)Generating gas usage report...$(NC)"
	forge test --gas-report

quick-test: build test ## Quick build and test
	@echo "$(GREEN)Quick test complete!$(NC)"

dev-setup: install build test ## Complete development setup
	@echo "$(GREEN)Development setup complete!$(NC)"

ci-test: install build test lint ## Complete CI test suite
	@echo "$(GREEN)CI test suite passed!$(NC)"

# Show help by default
.DEFAULT_GOAL := help