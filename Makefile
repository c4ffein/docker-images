.PHONY: help build test run stop logs shell clean clean-all push rebuild check info watch-logs \
	nginx-build nginx-test nginx-e2e nginx-run nginx-stop nginx-logs nginx-shell nginx-clean nginx-push nginx-rebuild \
	dev-build dev-test dev-run dev-stop dev-shell dev-clean

# Default target
.DEFAULT_GOAL := help

# Docker Hub configuration. DOCKER_REGISTRY is empty by default so the local
# image name matches what docker-compose.yml and the systemd unit expect
# (nginx-acme:latest). Set it to push: make nginx-push DOCKER_REGISTRY=youruser
DOCKER_REGISTRY ?=
DOCKER_TAG ?= latest

NGINX_IMAGE := $(if $(DOCKER_REGISTRY),$(DOCKER_REGISTRY)/,)nginx-acme:$(DOCKER_TAG)
DEV_IMAGE   := $(if $(DOCKER_REGISTRY),$(DOCKER_REGISTRY)/,)dev-env:$(DOCKER_TAG)

# Host port used by the nginx smoke test
NGINX_TEST_PORT ?= 8080

# Image list
IMAGES := nginx dev

# Colors for output
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m

##@ General

help: ## Display this help message
	@echo "$(COLOR_BOLD)Docker Images Build System$(COLOR_RESET)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(COLOR_BLUE)<target>$(COLOR_RESET)\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  $(COLOR_BLUE)%-15s$(COLOR_RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(COLOR_BOLD)%s$(COLOR_RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

build: ## Build all Docker images
	@echo "$(COLOR_GREEN)Building all images...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-build || exit 1; \
	done
	@echo "$(COLOR_GREEN)All images built successfully!$(COLOR_RESET)"

dev-build: ## Build dev environment image
	@echo "$(COLOR_YELLOW)Building dev image...$(COLOR_RESET)"
	@docker build -t $(DEV_IMAGE) dev
	@echo "$(COLOR_GREEN)dev image built: $(DEV_IMAGE)$(COLOR_RESET)"

nginx-build: ## Build nginx image
	@echo "$(COLOR_YELLOW)Building nginx image...$(COLOR_RESET)"
	@cd nginx && docker compose build
	@docker tag nginx-acme:latest $(NGINX_IMAGE)
	@echo "$(COLOR_GREEN)nginx image built: $(NGINX_IMAGE)$(COLOR_RESET)"

##@ Test
# These targets are what CI runs too (see .github/workflows), so keep them as
# the single definition of "does this image work".

test: ## Test all Docker images
	@echo "$(COLOR_GREEN)Testing all images...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-test || exit 1; \
	done
	@echo "$(COLOR_GREEN)All images tested successfully!$(COLOR_RESET)"

dev-test: ## Test dev environment image (toolchain on PATH, runs as dev)
	@echo "$(COLOR_YELLOW)Testing dev image...$(COLOR_RESET)"
	@echo "  → Toolchain is on PATH..."
	@docker run --rm $(DEV_IMAGE) bash -c 'set -e; \
		python --version; \
		uv --version; \
		bun --version; \
		cargo --version; \
		git --version; \
		nvim --version | head -1; \
		just --version; \
		gh --version | head -1'
	@echo "  → Runs as the dev user..."
	@test "$$(docker run --rm $(DEV_IMAGE) whoami)" = "dev"
	@echo "$(COLOR_GREEN)dev image tests passed!$(COLOR_RESET)"

nginx-test: ## Test nginx image (module, config, HTTP, health check)
	@echo "$(COLOR_YELLOW)Testing nginx image...$(COLOR_RESET)"
	@NGINX_TEST_PORT=$(NGINX_TEST_PORT) nginx/test/run-smoke.sh $(NGINX_IMAGE)
	@echo "$(COLOR_GREEN)nginx image tests passed!$(COLOR_RESET)"

nginx-e2e: ## Run the end-to-end ACME test (Pebble, offline, no domain needed)
	@echo "$(COLOR_YELLOW)Running nginx ACME end-to-end test...$(COLOR_RESET)"
	@nginx/test/run-e2e.sh
	@echo "$(COLOR_GREEN)nginx end-to-end test passed!$(COLOR_RESET)"

##@ Run

run: ## Run all services with docker-compose
	@echo "$(COLOR_GREEN)Starting all services...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-run; \
	done

dev-run: ## Run dev environment container (repo mounted at ~/workspace)
	@echo "$(COLOR_YELLOW)Starting dev environment...$(COLOR_RESET)"
	@docker run -d --name dev-env -v $(CURDIR):/home/dev/workspace $(DEV_IMAGE) sleep infinity > /dev/null
	@echo "$(COLOR_GREEN)dev environment is running - make dev-shell to enter$(COLOR_RESET)"

nginx-run: ## Run nginx container
	@echo "$(COLOR_YELLOW)Starting nginx...$(COLOR_RESET)"
	@cd nginx && docker compose up -d
	@echo "$(COLOR_GREEN)nginx is running at http://localhost$(COLOR_RESET)"

stop: ## Stop all running containers
	@echo "$(COLOR_YELLOW)Stopping all services...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-stop 2>/dev/null || true; \
	done
	@echo "$(COLOR_GREEN)All services stopped$(COLOR_RESET)"

dev-stop: ## Stop dev environment container
	@echo "$(COLOR_YELLOW)Stopping dev environment...$(COLOR_RESET)"
	@docker rm -f dev-env 2>/dev/null || true

dev-shell: ## Open shell in dev container
	@docker exec -it -w /home/dev/workspace dev-env /bin/bash -l

dev-clean: ## Clean dev resources
	@docker rm -f dev-env 2>/dev/null || true
	@docker rmi -f $(DEV_IMAGE) 2>/dev/null || true

nginx-stop: ## Stop nginx container
	@echo "$(COLOR_YELLOW)Stopping nginx...$(COLOR_RESET)"
	@cd nginx && docker compose down

##@ Logs

logs: nginx-logs ## View logs from all services

nginx-logs: ## View nginx logs
	@cd nginx && docker compose logs -f

##@ Utilities

shell: nginx-shell ## Open a shell in the nginx container

nginx-shell: ## Open shell in nginx container
	@docker exec -it nginx-acme /bin/sh

##@ Clean

clean: ## Clean all Docker images, containers, and volumes
	@echo "$(COLOR_YELLOW)Cleaning up...$(COLOR_RESET)"
	@$(MAKE) stop
	@echo "  → Removing containers..."
	@for image in $(IMAGES); do \
		$(MAKE) $$image-clean 2>/dev/null || true; \
	done
	@echo "  → Removing images..."
	@docker images | grep -E 'nginx-acme|dev-env' | awk '{print $$3}' | xargs -r docker rmi -f 2>/dev/null || true
	@echo "  → Removing build cache..."
	@docker builder prune -f > /dev/null 2>&1 || true
	@echo "$(COLOR_GREEN)Cleanup complete!$(COLOR_RESET)"

nginx-clean: ## Clean nginx resources
	@cd nginx && docker compose down -v 2>/dev/null || true
	@docker rm -f nginx-acme nginx-acme-smoke 2>/dev/null || true

clean-all: clean ## Deep clean including volumes and build cache
	@echo "$(COLOR_YELLOW)Performing deep clean...$(COLOR_RESET)"
	@docker volume prune -f
	@docker builder prune -af
	@echo "$(COLOR_GREEN)Deep clean complete!$(COLOR_RESET)"

##@ Publish

push: ## Push all images to Docker Hub
	@echo "$(COLOR_GREEN)Pushing images to Docker Hub...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-push || exit 1; \
	done
	@echo "$(COLOR_GREEN)All images pushed successfully!$(COLOR_RESET)"

nginx-push: ## Push nginx image to Docker Hub (needs DOCKER_REGISTRY=youruser)
	@test -n "$(DOCKER_REGISTRY)" || (echo "$(COLOR_YELLOW)Set DOCKER_REGISTRY first, e.g. make nginx-push DOCKER_REGISTRY=youruser$(COLOR_RESET)"; exit 1)
	@echo "$(COLOR_YELLOW)Pushing $(NGINX_IMAGE)...$(COLOR_RESET)"
	@docker push $(NGINX_IMAGE)
	@echo "$(COLOR_GREEN)Pushed $(NGINX_IMAGE)$(COLOR_RESET)"

##@ Development

rebuild: clean build ## Clean and rebuild all images

nginx-rebuild: nginx-clean nginx-build ## Clean and rebuild nginx image

watch-logs: ## Watch logs from all running containers
	@docker compose -f nginx/docker-compose.yml logs -f

check: ## Check system requirements and configuration
	@echo "$(COLOR_BOLD)System Check$(COLOR_RESET)"
	@echo "  → Docker version:"
	@docker --version
	@echo "  → Docker Compose version:"
	@docker compose version
	@echo "  → Available images:"
	@docker images | grep -E "REPOSITORY|nginx-acme|dev-env" || echo "    No images built yet"
	@echo "  → Running containers:"
	@docker ps | grep -E "CONTAINER|nginx-acme|dev-env" || echo "    No containers running"

info: ## Display image information
	@echo "$(COLOR_BOLD)Image Information$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BLUE)nginx-acme$(COLOR_RESET)"
	@docker images $(NGINX_IMAGE) --format "  Size: {{.Size}}\n  Created: {{.CreatedSince}}\n  ID: {{.ID}}" 2>/dev/null | grep . || echo "  Not built yet"
	@echo ""
	@echo "$(COLOR_BLUE)dev-env$(COLOR_RESET)"
	@docker images $(DEV_IMAGE) --format "  Size: {{.Size}}\n  Created: {{.CreatedSince}}\n  ID: {{.ID}}" 2>/dev/null | grep . || echo "  Not built yet"
