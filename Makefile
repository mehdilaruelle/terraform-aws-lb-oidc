# Local equivalents of the CI jobs. None of them needs an AWS account.

TF ?= terraform

.PHONY: help fmt validate test lint docs examples all clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

all: fmt validate test lint docs examples ## Run every check

fmt: ## Format every Terraform file
	$(TF) fmt -recursive

validate: ## Initialise and validate the module
	$(TF) init -backend=false
	$(TF) validate

test: ## Run the test suite against mocked providers
	$(TF) test

lint: ## Lint the module and the examples
	tflint --init --recursive
	tflint --recursive --minimum-failure-severity=error

docs: ## Regenerate the input and output tables in README.md
	terraform-docs .

examples: ## Validate every example
	@for dir in examples/*/; do \
		echo "==> $$dir"; \
		$(TF) -chdir=$$dir init -backend=false >/dev/null; \
		$(TF) -chdir=$$dir validate; \
	done

clean: ## Remove local Terraform state and plugin caches
	find . -type d -name .terraform -prune -exec rm -rf {} +
	find examples -name .terraform.lock.hcl -delete
