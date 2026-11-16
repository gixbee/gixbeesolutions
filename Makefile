# Gixbee — Docker commands
# Usage: make <command>

COMPOSE := docker compose -f docker-compose.yml

.PHONY: help dev dev-bg prod down logs ps shell-backend shell-db clean

help:
	@echo ""
	@echo "  Gixbee Docker Commands"
	@echo "  ─────────────────────────────────────────"
	@echo "  make dev          Start in development mode (hot reload)"
	@echo "  make prod         Start in production mode"
	@echo "  make down         Stop all containers"
	@echo "  make logs         Tail logs from all containers"
	@echo "  make ps           Show running containers"
	@echo "  make shell-backend  Open shell inside Rust API container"
	@echo "  make shell-db     Open psql inside postgres container"
	@echo "  make clean        Remove containers, volumes, images"
	@echo ""

dev:
	$(COMPOSE) -f docker-compose.dev.yml up --build

dev-bg:
	$(COMPOSE) -f docker-compose.dev.yml up --build -d

prod:
	$(COMPOSE) up --build -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

logs-backend:
	$(COMPOSE) logs -f backend_rust

logs-db:
	$(COMPOSE) logs -f postgres

ps:
	$(COMPOSE) ps

shell-backend:
	docker exec -it $$(docker ps -qf "name=backend_rust") sh

shell-db:
	docker exec -it gixbee_postgres psql -U postgres -d gixbee_db

shell-redis:
	docker exec -it gixbee_redis redis-cli

clean:
	$(COMPOSE) down -v --rmi local
	@echo "Removed containers, volumes, and local images"