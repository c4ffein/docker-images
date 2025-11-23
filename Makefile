.PHONY: help build clean test push run stop logs shell nginx-build nginx-test nginx-clean nginx-run nginx-stop

# Default target
.DEFAULT_GOAL := help

# Docker Hub configuration
DOCKER_REGISTRY ?= nginx
DOCKER_TAG ?= latest

# Image list
IMAGES := nginx

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
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(COLOR_BLUE)<target>$(COLOR_RESET)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(COLOR_BLUE)%-15s$(COLOR_RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(COLOR_BOLD)%s$(COLOR_RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

build: ## Build all Docker images
	@echo "$(COLOR_GREEN)Building all images...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-build || exit 1; \
	done
	@echo "$(COLOR_GREEN)All images built successfully!$(COLOR_RESET)"

nginx-build: ## Build nginx image
	@echo "$(COLOR_YELLOW)Building nginx image...$(COLOR_RESET)"
	@cd nginx && docker compose build
	@docker tag nginx-acme:latest $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG)
	@echo "$(COLOR_GREEN)nginx image built: $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG)$(COLOR_RESET)"

##@ Test

test: ## Test all Docker images
	@echo "$(COLOR_GREEN)Testing all images...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-test || exit 1; \
	done
	@echo "$(COLOR_GREEN)All images tested successfully!$(COLOR_RESET)"

nginx-test: ## Test nginx image
	@echo "$(COLOR_YELLOW)Testing nginx image...$(COLOR_RESET)"
	@echo "  → Testing nginx binary..."
	@docker run --rm $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG) nginx -v
	@echo "  → Testing configuration..."
	@docker run --rm $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG) nginx -t
	@echo "  → Checking ACME module..."
	@docker run --rm $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG) ls -lh /usr/lib/nginx/modules/ngx_http_acme_module.so
	@echo "  → Testing HTTP server..."
	@docker run -d --name nginx-test -p 8080:80 $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG) > /dev/null
	@sleep 2
	@curl -sf http://localhost:8080 > /dev/null && echo "  → HTTP server responding ✓" || (docker stop nginx-test > /dev/null 2>&1; docker rm nginx-test > /dev/null 2>&1; echo "  → HTTP server test failed ✗"; exit 1)
	@docker stop nginx-test > /dev/null 2>&1
	@docker rm nginx-test > /dev/null 2>&1
	@echo "$(COLOR_GREEN)nginx image tests passed!$(COLOR_RESET)"

##@ Run

run: ## Run all services with docker-compose
	@echo "$(COLOR_GREEN)Starting all services...$(COLOR_RESET)"
	@for image in $(IMAGES); do \
		$(MAKE) $$image-run; \
	done

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
	@docker exec -it nginx-acme /bin/bash

##@ Clean

clean: ## Clean all Docker images, containers, and volumes
	@echo "$(COLOR_YELLOW)Cleaning up...$(COLOR_RESET)"
	@$(MAKE) stop
	@echo "  → Removing containers..."
	@for image in $(IMAGES); do \
		$(MAKE) $$image-clean 2>/dev/null || true; \
	done
	@echo "  → Removing images..."
	@docker images | grep -E 'nginx-acme|$(DOCKER_REGISTRY)/nginx-acme' | awk '{print $$3}' | xargs -r docker rmi -f 2>/dev/null || true
	@echo "  → Removing build cache..."
	@docker builder prune -f > /dev/null 2>&1 || true
	@echo "$(COLOR_GREEN)Cleanup complete!$(COLOR_RESET)"

nginx-clean: ## Clean nginx resources
	@cd nginx && docker compose down -v 2>/dev/null || true
	@docker rm -f nginx-acme nginx-test 2>/dev/null || true

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

nginx-push: ## Push nginx image to Docker Hub
	@echo "$(COLOR_YELLOW)Pushing $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG)...$(COLOR_RESET)"
	@docker push $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG)
	@echo "$(COLOR_GREEN)Pushed $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG)$(COLOR_RESET)"

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
	@docker images | grep -E "REPOSITORY|nginx-acme" || echo "    No images built yet"
	@echo "  → Running containers:"
	@docker ps | grep -E "CONTAINER|nginx-acme" || echo "    No containers running"

info: ## Display image information
	@echo "$(COLOR_BOLD)Image Information$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BLUE)nginx-acme$(COLOR_RESET)"
	@docker images $(DOCKER_REGISTRY)/nginx-acme:$(DOCKER_TAG) --format "  Size: {{.Size}}\n  Created: {{.CreatedSince}}\n  ID: {{.ID}}" 2>/dev/null || echo "  Not built yet"
