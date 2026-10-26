COMPOSE := docker compose

.PHONY: help up down build logs ps migrate revision test test-backend test-frontend lint fmt clean shell-backend shell-db deploy-backend destroy-backend logs-backend migrate-backend domain-frontend domain-backend deploy-frontend destroy-frontend github-role infra-init infra-check infra-plan infra-output infra-env report-now logs-report-builder logs-report-mailer llm-hello parse logs-ai

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack (detached)
	$(COMPOSE) up -d --build

down: ## Stop the stack
	$(COMPOSE) down

clean: ## Stop the stack and wipe the database volume
	$(COMPOSE) down -v

build: ## Rebuild images
	$(COMPOSE) build

logs: ## Tail all logs
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add x"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

test: test-backend test-frontend ## Run all tests

test-backend: ## Run backend tests
	$(COMPOSE) exec backend pytest

test-frontend: ## Run frontend tests
	$(COMPOSE) exec frontend pnpm test

lint: ## Lint both sides
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend pnpm lint

fmt: ## Format both sides
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend pnpm format

shell-backend: ## Shell into the backend container
	$(COMPOSE) exec backend bash

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-spry} -d $${POSTGRES_DB:-spry}

deploy-backend: ## Build + push the image (tagged with the commit SHA), roll the Lambda, migrate, write BACKEND_URL to .env
	./scripts/deploy-backend.sh

destroy-backend: ## Delete the backend stack, Aurora cluster included
	./scripts/destroy-backend.sh

logs-backend: ## Tail the deployed backend's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-spry}-backend --follow --since 10m

migrate-backend: ## Re-run migrations on the deployed backend (deploy-backend already does)
	aws lambda invoke --function-name $${PROJECT_NAME:-spry}-backend \
		--cli-binary-format raw-in-base64-out --payload '{"action":"migrate"}' /dev/stdout

domain-frontend: ## Custom domain + HTTPS for the site: make domain-frontend DOMAIN=app.example.com
	./scripts/domain.sh frontend domain

domain-backend: ## Custom domain + HTTPS for the API: make domain-backend DOMAIN=api.example.com
	./scripts/domain.sh backend domain

deploy-frontend: ## Build the static export against BACKEND_URL and ship it to S3 + CloudFront
	./scripts/deploy-frontend.sh

destroy-frontend: ## Delete the frontend stack (bucket + distribution)
	./scripts/destroy-frontend.sh

github-role: ## Create the IAM role GitHub Actions assumes to deploy (OIDC, no keys)
	./scripts/github-role.sh

# Sign-in, the weekly report and the agenda parser are Terraform (infra/*.tf),
# applied by HCP Terraform after a merge to main. There is no infra-apply
# here on purpose: a laptop plans, the workspace applies.
infra-init: ## terraform init against the HCP Terraform workspace (needs `terraform login` once)
	terraform -chdir=infra init

infra-check: ## terraform fmt -check + validate - touches nothing in the cloud
	terraform -chdir=infra fmt -check -recursive
	terraform -chdir=infra validate

infra-plan: ## Speculative plan, run in HCP Terraform - shows what a merge would change
	terraform -chdir=infra plan

infra-output: ## Show the infrastructure's outputs (user pool, queue, parser URL, ...)
	terraform -chdir=infra output

infra-env: ## Copy the outputs the frontend build needs (AUTH_*, PARSER_URL) into .env
	./scripts/infra-env.sh

report-now: ## Build a report on demand: make report-now [WEEK=2026-W39]
	./scripts/report-now.sh

logs-report-builder: ## Tail the report-builder's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-spry}-report-builder --follow --since 10m

logs-report-mailer: ## Tail the report-mailer's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-spry}-report-mailer --follow --since 10m

llm-hello: ## Call Claude on Bedrock once from your laptop (Lab 6, Part 1)
	./scripts/llm-hello.sh

parse: ## Parse pasted text into an agenda from your laptop: make parse TEXT="..."
	./scripts/parse.sh

logs-ai: ## Tail the agenda-parser's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-spry}-agenda-parser --follow --since 10m
